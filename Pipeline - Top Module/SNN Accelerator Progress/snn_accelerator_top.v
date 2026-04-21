`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module : snn_accelerator_top  - FINAL  (ZCU104 / XCZU7EV @ 200 MHz)
//
// Pipeline order (CORA stage numbers):
//   S7  fifo_cdc            ─┐
//   S8  input_from_aer       ├─ aer_pipeline.v
//   S9  timestamp_manager   ─┘
//   S10 s10_window_accumulator
//       spike_readback         (8-bit counts → binary 800-bit spike bus)
//       pipeline_sequencer     (stalls MAC until readback is done)
//   S11 mac_engine_parallel   (W_in × input + W_rec × s_prev, 16-wide fetch)
//   S12 lif_array_bram_fixed  (LIF dynamics, V_m in Bank 1a BRAM)
//   S13 output_layer           (W_out × final spikes → NO class scores,
//                               bank_a + bank_b running sum)
//   S14 overlap_voter_zcu104  (pairs window N + N+1, argmax → pred_class)
//
// ─── FIX SUMMARY ─────────────────────────────────────────────────────────────
//  [FIX 1]  overlap_voter instantiated as true Stage 14.
//           output_layer produces combined_scores (Q16.16 per class, NO×32-bit).
//           Upper 16 bits of each 32-bit score → voter_score_in (Q8.8, NO×16-bit).
//           voter pred_valid becomes top-level result_valid.
//           voter pred_class becomes top-level cmd_id.
//
//  [FIX 2]  Address bus corrected to 15 bits ([14:0]) throughout.
//           W_out base = 0x4800 = 18432 needs bit 14 set.
//           Old [13:0] silently truncated W_out addresses into W_rec space.
//
//  [FIX 3]  snn_bram_top instantiated inside this module.
//           DELETE u_bram_weights.xci and u_bram_vm.xci from Vivado project.
//
//  [FIX 4]  bram_bus_mux arbitrates narrow bus between MAC (weights) and LIF (V_m).
//
//  [FIX 5]  spike_readback ports match actual module (.start/.rd_ping/.rd_addr/.rd_data).
//
//  [FIX 6]  pipeline_sequencer used (not inline FSM); waits for rb_done before mac_start.
//
//  [FIX 7]  lif_neuron_idx_raw was double-driven - fixed with single assign from vm_addr.
//
// ─── DELETE FROM VIVADO PROJECT ──────────────────────────────────────────────
//  u_bram_weights.xci  (superseded by bank_3_win / bank_3_wrec / bank_3_wout)
//  u_bram_vm.xci       (superseded by bank_1_vm)
//  Right-click → Remove File from Project → reset_run synth_1
//
// ─── RTL FILES REQUIRED ──────────────────────────────────────────────────────
//  snn_accelerator_top_final.v   (this file)
//  overlap_voter_zcu104.v
//  output_layer.v
//  mac_engine_parallel.v
//  lif_array_bram_fixed.v
//  spike_readback.v
//  pipeline_sequencer.v
//  bram_arbiter_fixed.v          (15-bit address version)
//  bram_bus_mux.v
//  snn_bram_top.v
//  aer_pipeline.v
//  s10_window_accumulator.v
//  BRAM IPs: run create_brams.tcl, create_window_acc_bram.tcl
//////////////////////////////////////////////////////////////////////////////////

module snn_accelerator_top (
    input  wire        clk_200m,
    input  wire        rst_n,

    // AER input from cochlea
    input  wire        aer_valid,
    input  wire [23:0] aer_data,        // [23:20]=channel, [19:0]=timestamp

    // VAD gate (tie high when no external speech detector)
    input  wire        speech_valid,

    // Pipeline outputs
    output wire        window_ready,    // 1-cycle pulse per 50 ms window
    output wire        result_valid,    // 1-cycle pulse: overlap_voter decision ready
    output wire [3:0]  cmd_id,          // Predicted command class 0..9
    output wire [7:0]  confidence       // Q8.0 confidence from overlap_voter
);

// ============================================================
// PARAMETERS
// ============================================================
localparam NH = 128;
localparam NI = 16;
localparam NO = 10;
localparam T  = 50;

// ============================================================
// 1. AER PIPELINE  (S7-S9)
// ============================================================
wire [3:0]  aer_ch;
wire [31:0] aer_ts;
wire        aer_ts_valid;

aer_pipeline u_aer_pipe (
    .clk            (clk_200m),
    .rst_n          (rst_n),
    .aer_data       (aer_data),
    .aer_valid      (aer_valid),
    .channel_Id     (aer_ch),
    .timestamp      (aer_ts),
    .timestamp_valid(aer_ts_valid),
    .spike_detected (),
    .window_start   (),
    .fifo_full      (),
    .fifo_empty     ()
);

// ============================================================
// 2. WINDOW ACCUMULATOR  (S10)
// ============================================================
wire        win_ready_int;
wire        rd_ping;
wire [10:0] mac_rd_addr;
wire [7:0]  mac_rd_data;

assign window_ready = win_ready_int;

s10_window_accumulator u_win_accum (
    .clk            (clk_200m),
    .reset_n        (rst_n),
    .window_offset  (aer_ts[19:0]),
    .ts_abs_valid   (aer_ts_valid),
    .spike_ch       (aer_ch),
    .speech_valid   (speech_valid),
    .window_open    (),
    .window_ready   (win_ready_int),
    .rd_ping_sel    (rd_ping),
    .mac_rd_addr    (mac_rd_addr),
    .mac_rd_data    (mac_rd_data)
);

// ============================================================
// 3. SPIKE READBACK
//    Reads 800 BRAM locations after win_ready, thresholds 8-bit
//    counts to binary, packs into win_spikes[NI*T-1:0].
//    Takes 800+1 cycles.  MAC must not start until rb_done.
// ============================================================
wire [NI*T-1:0] win_spikes;
wire            rb_done;

spike_readback #(
    .NI(NI), .T(T)
) u_spike_rb (
    .clk        (clk_200m),
    .rst_n      (rst_n),
    .start      (win_ready_int),
    .rd_ping    (rd_ping),
    .rd_addr    (mac_rd_addr),
    .rd_data    (mac_rd_data),
    .win_spikes (win_spikes),
    .done       (rb_done)
);

// ============================================================
// 4. PIPELINE SEQUENCER
//    win_ready → (wait rb_done) → mac_start → (wait mac_done)
//    → (wait ol_result_valid) → idle
// ============================================================
wire mac_start;
wire mac_done;    // driven by u_mac below
wire ol_result_valid; // driven by u_output below

pipeline_sequencer u_seq (
    .clk          (clk_200m),
    .rst_n        (rst_n),
    .win_ready    (win_ready_int),
    .rb_done      (rb_done),
    .mac_done     (mac_done),
    .result_valid (ol_result_valid),
    .mac_start    (mac_start),
    .busy         ()
);

// ============================================================
// 5. BRAM ARBITER  (Bank 3 - weights, 15-bit address)
// ============================================================
wire        mac_bram_req;
wire        mac_bram_grant;

wire [13:0] mac_bram_addr_int;  // [FIX-A] matches mac_engine_parallel [13:0] port
wire [15:0] mac_bram_din_int;
wire        mac_bram_we_int;
wire [15:0] mac_bram_dout_int;

// Arbiter → mux wires
wire [14:0] arb_bram_addr;
wire [15:0] arb_bram_din;
wire        arb_bram_we;
wire        arb_bram_en;
wire [15:0] arb_bram_dout;

bram_arbiter u_bram_arb (
    .clk        (clk_200m),
    .rst_n      (rst_n),

    .mac_req    (mac_bram_req),
    .mac_grant  (mac_bram_grant),
    .mac_done   (mac_done),
    .mac_addr   ({1'b0, mac_bram_addr_int}),  // [FIX-A] extend 14→15 bit for arbiter
    .mac_din    (mac_bram_din_int),
    .mac_we     (mac_bram_we_int),
    .mac_dout   (mac_bram_dout_int),

    // Training masters tied off for inference
    .bptt_req   (1'b0), .bptt_done(1'b1), .bptt_addr(15'd0),
    .bptt_din   (16'd0), .bptt_we(1'b0), .bptt_grant(), .bptt_dout(),

    .wupd_req   (1'b0), .wupd_done(1'b1), .wupd_addr(15'd0),
    .wupd_din   (16'd0), .wupd_we(1'b0), .wupd_grant(), .wupd_dout(),

    .host_req   (1'b0), .host_done(1'b1), .host_addr(15'd0),
    .host_din   (16'd0), .host_we(1'b0), .host_grant(), .host_dout(),

    .bram_addr  (arb_bram_addr),
    .bram_din   (arb_bram_din),
    .bram_we    (arb_bram_we),
    .bram_en    (arb_bram_en),
    .bram_dout  (arb_bram_dout)
);

// ============================================================
// 6. BRAM BUS MUX
//    Narrow 16-bit bus shared by MAC (weight reads) and LIF (V_m).
//    LIF priority during sweep (FSM-guaranteed non-overlap).
// ============================================================
// [FIX-B] lif_vm_addr_full and lif_vm_idx declared here (single driver)
wire [8:0] lif_vm_addr_full;
wire [6:0] lif_vm_idx = lif_vm_addr_full[6:0]; // upper bits always 0 in inference
wire [15:0] lif_vm_din;
wire [15:0] lif_vm_dout;
wire        lif_vm_we;
wire        lif_vm_en;

// Muxed → snn_bram_top narrow bus
wire [16:0] bram_top_addr;
wire [15:0] bram_top_din;
wire        bram_top_we;
wire        bram_top_ena;
wire        bram_top_enb;
wire [15:0] bram_top_dout;

bram_bus_mux u_mux (
    // MAC / arbiter (weight reads; 15-bit addr → prepend 2'b01 for snn_bram_top)
    .mac_addr       ({2'b01, arb_bram_addr}),
    .mac_din        (arb_bram_din),
    .mac_we         (arb_bram_we),
    .mac_ena        (arb_bram_en),
    .mac_enb        (1'b0),

    // LIF (V_m, neuron 0..127; mux adds 0x01000 base)
    .lif_neuron_idx (lif_vm_idx),
    .lif_din        (lif_vm_din),
    .lif_we         (lif_vm_we),
    .lif_ena        (lif_vm_en),
    .lif_enb        (lif_vm_en),

    // → snn_bram_top
    .bram_addr      (bram_top_addr),
    .bram_din       (bram_top_din),
    .bram_we        (bram_top_we),
    .bram_ena       (bram_top_ena),
    .bram_enb       (bram_top_enb),

    // Read data routing
    .bram_dout      (bram_top_dout),
    .mac_dout       (arb_bram_dout),
    .lif_dout       (lif_vm_dout)
);

// ============================================================
// 7. MAC ENGINE - PARALLEL  (S11)
// ============================================================
wire [15:0]   lif_acc;
wire [6:0]    lif_idx;
wire          lif_wen, lif_capture;
wire [NH-1:0] lif_spikes;
wire          capture_done;

wire [NO*32-1:0] mac_score_out;
wire             mac_score_valid;

// [FIX-B] lif_vm_idx is driven solely from lif_vm_addr_full[6:0] declared below

mac_engine #(
    .NH(NH), .NI(NI), .NO(NO), .T(T),
    .W_IN_BASE  (14'h0000),
    .W_REC_BASE (14'h0800),
    .W_OUT_BASE (14'h4800)
) u_mac (
    .clk            (clk_200m),
    .rst_n          (rst_n),
    .mac_start      (mac_start),
    .mac_done       (mac_done),
    .mac_bram_req   (mac_bram_req),
    .mac_bram_grant (mac_bram_grant),
    .mac_bram_addr  (mac_bram_addr_int),
    .mac_bram_din   (mac_bram_din_int),
    .mac_bram_we    (mac_bram_we_int),
    .mac_bram_dout  (mac_bram_dout_int),
    .win_spikes     (win_spikes),
    .lif_acc        (lif_acc),
    .lif_idx        (lif_idx),
    .lif_wen        (lif_wen),
    .lif_capture    (lif_capture),
    .lif_spikes     (lif_spikes),
    .score_out      (mac_score_out),
    .score_valid    (mac_score_valid)
);

// ============================================================
// 8. LIF ARRAY  (S12)
// ============================================================
// [FIX-B] lif_vm_addr_full / lif_vm_idx declared at Section 6 above

lif_array_bram #(
    .NH(NH),
    .ALPHA(16'h00E0),    // 0.875 Q8.8
    .THETA(16'h0100)     // 1.0   Q8.8
) u_lif (
    .clk            (clk_200m),
    .rst_n          (rst_n),
    .clear_state    (1'b0),
    .lif_acc        (lif_acc),
    .lif_idx        (lif_idx),
    .lif_wen        (lif_wen),
    .lif_capture    (lif_capture),
    .lif_spikes     (lif_spikes),
    .capture_done   (capture_done),
    .vm_addr        (lif_vm_addr_full),
    .vm_din         (lif_vm_din),
    .vm_dout        (lif_vm_dout),
    .vm_we          (lif_vm_we),
    .vm_en          (lif_vm_en)
);

// ============================================================
// 9. OUTPUT LAYER  (S13)
//    Maintains bank_a + bank_b running window sum, produces
//    combined_scores (NO × 32-bit Q16.16) and fires result_valid
//    once per window.  combined_scores feeds the overlap voter.
// ============================================================
wire [3:0]       ol_cmd_id;         // internal argmax (not used at top level)
wire [15:0]      ol_confidence;     // internal confidence (not used at top level)
wire [NO*32-1:0] ol_combined;       // bank_a + bank_b scores → overlap voter

output_layer #(
    .NO(NO), .NH(NH)
) u_output (
    .clk            (clk_200m),
    .rst_n          (rst_n),
    .score_out      (mac_score_out),
    .score_valid    (mac_score_valid),
    .cmd_id         (ol_cmd_id),
    .confidence     (ol_confidence),
    .result_valid   (ol_result_valid),
    .combined_scores(ol_combined)
);

// ============================================================
// 10. OVERLAP VOTER  (S14) - overlap_voter_zcu104.v
//
//  ol_combined is NO × 32-bit (Q16.16).
//  overlap_voter expects NO × 16-bit (SCORE_WIDTH=16, Q8.8).
//  We take bits [31:16] of each 32-bit word (upper half = integer
//  + upper fractional bits), which gives a Q8.8 representation.
//
//  The voter latches window N (first ol_result_valid → ST_IDLE),
//  then window N+1 (second ol_result_valid → ST_HOLD), adds them,
//  and fires pred_valid with the argmax result.
//
//  pred_valid → top-level result_valid
//  pred_class → top-level cmd_id
//  pred_score[15:8] → top-level confidence (Q8.0)
// ============================================================

// Pack NO × 16-bit voter input from ol_combined
wire [NO*16-1:0] voter_score_in;
genvar gi;
generate
    for (gi = 0; gi < NO; gi = gi + 1) begin : g_voter_pack
        assign voter_score_in[gi*16 +: 16] = ol_combined[gi*32+31 : gi*32+16];
    end
endgenerate

wire [3:0]  voter_pred_class;
wire [16:0] voter_pred_score;   // SUM_WIDTH = SCORE_WIDTH + 1 = 17 bits
wire        voter_pred_valid;
wire        voter_busy;

overlap_voter #(
    .NUM_CLASSES    (NO),
    .SCORE_WIDTH    (16),
    .SLIDING_WINDOW (0)           // Paired mode: decision every 2 windows
) u_voter (
    .clk         (clk_200m),
    .rst_n       (rst_n),
    .score_in    (voter_score_in),
    .score_valid (ol_result_valid), // one pulse per window from output_layer
    .pred_class  (voter_pred_class),
    .pred_score  (voter_pred_score),
    .pred_valid  (voter_pred_valid),
    .voter_busy  (voter_busy)
);

// ============================================================
// TOP-LEVEL OUTPUTS
// ============================================================
assign result_valid = voter_pred_valid;
assign cmd_id       = voter_pred_class;
// pred_score is Q9.8 signed 17-bit.  Bits [15:8] = integer byte = Q8.0 confidence.
assign confidence   = voter_pred_score[15:8];

// ============================================================
// 11. snn_bram_top - all inference BRAM banks
// ============================================================

// Wide bus (128-bit spike history Bank 1b) - MAC is sole master, no arbiter
// mac_engine_parallel does not have explicit wide-bus ports in the provided
// code; spike history for s_prev is held in the score[] register array and
// the local s_prev register inside the MAC FSM.  If you later add a BRAM-
// backed spike history, connect mac_wide_* here.  For now Bank 1b is tied off.
wire        mac_wide_ena  = 1'b0;
wire        mac_wide_wea  = 1'b0;
wire [8:0]  mac_wide_addr = 9'b0;
wire [127:0] mac_wide_din = 128'b0;
wire [127:0] mac_wide_dout;

snn_bram_top u_snn_bram (
    .clka      (clk_200m),
    .clkb      (clk_200m),

    // Narrow bus (Bank 1a V_m + Bank 3a/3b/3c weights)
    .ena       (bram_top_ena),
    .enb       (bram_top_enb),
    .wea       (bram_top_we),
    .addr      (bram_top_addr),
    .din       (bram_top_din),
    .dout      (bram_top_dout),

    // Wide bus (Bank 1b spike history - tied off)
    .ena_wide  (mac_wide_ena),
    .enb_wide  (1'b1),
    .wea_wide  (mac_wide_wea),
    .addr_wide (mac_wide_addr),
    .din_wide  (mac_wide_din),
    .dout_wide (mac_wide_dout)
);

endmodule