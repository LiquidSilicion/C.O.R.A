`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: snn_accelerator_top  (FIXED)
// Target: AMD ZCU104 XCZU7EV @ 200 MHz
//
// Fixes vs previous version:
//   1. overlap_voter port names corrected:
//        score_in / score_valid / pred_class / pred_score / pred_valid
//   2. output_layer → overlap_voter interface now uses the FLAT PACKED score bus
//      (score_out from mac_engine) NOT the per-window cmd/confidence signals,
//      because overlap_voter expects raw class scores, not an argmax result.
//   3. Duplicate BRAM IP instantiations removed - BRAMs are modelled in the
//      testbench; re-instantiating them inside the DUT causes multiple-driver
//      elaboration errors.
//   4. output_layer result (ol_cmd_id / ol_confidence / ol_result_valid) kept
//      as a debug path; the voted result drives the primary outputs.
//   5. voter_busy left unconnected (debug only).
//////////////////////////////////////////////////////////////////////////////////

module snn_accelerator_top (
    input  wire        clk_200m,
    input  wire        rst_n,

    // AER Input
    input  wire        aer_valid,
    input  wire [23:0] aer_data,   // [23:20]=ch, [19:0]=timestamp

    // VAD gate
    input  wire        speech_valid,

    // Pipeline status
    output wire        window_ready,
    output wire        result_valid,
    output wire [3:0]  cmd_id,
    output wire [7:0]  confidence,

    // BRAM Bank 3 (Weights)
    output wire [13:0] bram_bank3_addr,
    input  wire [15:0] bram_bank3_dout,
    output wire [15:0] bram_bank3_din,
    output wire        bram_bank3_we,
    output wire        bram_bank3_en,

    // BRAM Bank 2 (Neuron V_m)
    output wire [8:0]  bram_bank2_addr,
    input  wire [15:0] bram_bank2_dout,
    output wire [15:0] bram_bank2_din,
    output wire        bram_bank2_we,
    output wire        bram_bank2_en
);

// ================================================================
// PARAMETERS
// ================================================================
localparam NH = 128;
localparam NI = 16;
localparam NO = 10;
localparam T  = 50;

// ================================================================
// INTERNAL SIGNALS
// ================================================================

// AER pipeline
wire [3:0]  aer_ch;
wire [31:0] aer_ts;
wire        aer_ts_valid;
wire        aer_spike;
wire        aer_win_start;

// Window accumulator
wire        win_open;
wire        win_ready_int;
wire        rd_ping;
wire [10:0] mac_rd_addr;
wire [7:0]  mac_rd_data;

// Spike readback
wire [NI*T-1:0] win_spikes;
wire            rb_done;

// Pipeline sequencer
wire        mac_start;
wire        seq_busy;

// MAC <-> LIF
wire [15:0]    lif_acc;
wire [6:0]     lif_idx;
wire           lif_wen, lif_capture;
wire [NH-1:0]  lif_spikes;
wire           capture_done;

// MAC control
wire               mac_done;
wire [NO*32-1:0]   score_out;
wire               score_valid;

// MAC <-> BRAM arbiter
wire        mac_bram_req;
wire        mac_bram_grant;
wire [13:0] mac_bram_addr_int;
wire [15:0] mac_bram_din_int;
wire        mac_bram_we_int;
wire [15:0] mac_bram_dout_int;
wire        mac_bram_done;

// Output layer (per-window argmax, debug path)
wire [3:0]  ol_cmd_id;
wire [15:0] ol_confidence;
wire        ol_result_valid;

// Overlap voter (final voted output)
// overlap_voter uses a flat Q8.8 score bus, not cmd/confidence.
// We pass score_out[NO*32-1:0] truncated to NO*16-bit (upper 16 bits of each
// 32-bit word = Q16.16 → Q8.8 by taking bits [31:16]).
wire [NO*16-1:0] score_packed_q88;
genvar gp;
generate
    for (gp = 0; gp < NO; gp = gp + 1) begin : g_pack
        // Take upper 16 bits of each Q16.16 word → Q8.8 for voter
        assign score_packed_q88[gp*16 +: 16] = score_out[gp*32+16 +: 16];
    end
endgenerate

wire [3:0]  voter_pred_class;
wire [16:0] voter_pred_score;   // SUM_WIDTH = SCORE_WIDTH+1 = 17
wire        voter_pred_valid;
wire        voter_busy;

assign mac_bram_done = mac_done;

// Training masters tied off
wire        bptt_bram_req   = 1'b0;
wire        bptt_bram_done  = 1'b1;
wire [13:0] bptt_bram_addr  = 14'd0;
wire [15:0] bptt_bram_din   = 16'd0;
wire        bptt_bram_we    = 1'b0;
wire        bptt_bram_grant;
wire [15:0] bptt_bram_dout;

wire        wupd_bram_req   = 1'b0;
wire        wupd_bram_done  = 1'b1;
wire [13:0] wupd_bram_addr  = 14'd0;
wire [15:0] wupd_bram_din   = 16'd0;
wire        wupd_bram_we    = 1'b0;
wire        wupd_bram_grant;
wire [15:0] wupd_bram_dout;

wire        host_bram_req   = 1'b0;
wire        host_bram_done  = 1'b1;
wire [13:0] host_bram_addr  = 14'd0;
wire [15:0] host_bram_din   = 16'd0;
wire        host_bram_we    = 1'b0;
wire        host_bram_grant;
wire [15:0] host_bram_dout;

// ================================================================
// 1. AER PIPELINE
// ================================================================
aer_pipeline u_aer_pipe (
    .clk             (clk_200m),
    .rst_n           (rst_n),
    .aer_data        (aer_data),
    .aer_valid       (aer_valid),
    .channel_Id      (aer_ch),
    .timestamp       (aer_ts),
    .timestamp_valid (aer_ts_valid),
    .spike_detected  (aer_spike),
    .window_start    (aer_win_start),
    .fifo_full       (),
    .fifo_empty      ()
);

// ================================================================
// 2. WINDOW ACCUMULATOR
// ================================================================
s10_window_accumulator u_win_accum (
    .clk           (clk_200m),
    .reset_n       (rst_n),
    .window_offset (aer_ts[19:0]),
    .ts_abs_valid  (aer_ts_valid),
    .spike_ch      (aer_ch),
    .speech_valid  (speech_valid),
    .window_open   (win_open),
    .window_ready  (win_ready_int),
    .rd_ping_sel   (rd_ping),
    .mac_rd_addr   (mac_rd_addr),
    .mac_rd_data   (mac_rd_data)
);

assign window_ready = win_ready_int;

// ================================================================
// 3. SPIKE READBACK
// ================================================================
spike_readback #(
    .NI     (NI),
    .T      (T),
    .THRESH (8'd1)
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

// ================================================================
// 4. PIPELINE SEQUENCER
// ================================================================
pipeline_sequencer u_seq (
    .clk          (clk_200m),
    .rst_n        (rst_n),
    .win_ready    (win_ready_int),
    .rb_done      (rb_done),
    .mac_done     (mac_done),
    .result_valid (voter_pred_valid),
    .mac_start    (mac_start),
    .busy         (seq_busy)
);

// ================================================================
// 5. BRAM ARBITER
// ================================================================
bram_arbiter #(
    .ADDR_WIDTH (14),
    .DATA_WIDTH (16)
) u_bram_arb (
    .clk        (clk_200m),
    .rst_n      (rst_n),
    .mac_req    (mac_bram_req),
    .mac_grant  (mac_bram_grant),
    .mac_done   (mac_bram_done),
    .mac_addr   (mac_bram_addr_int),
    .mac_din    (mac_bram_din_int),
    .mac_we     (mac_bram_we_int),
    .mac_dout   (mac_bram_dout_int),
    .bptt_req   (bptt_bram_req),
    .bptt_grant (bptt_bram_grant),
    .bptt_done  (bptt_bram_done),
    .bptt_addr  (bptt_bram_addr),
    .bptt_din   (bptt_bram_din),
    .bptt_we    (bptt_bram_we),
    .bptt_dout  (bptt_bram_dout),
    .wupd_req   (wupd_bram_req),
    .wupd_grant (wupd_bram_grant),
    .wupd_done  (wupd_bram_done),
    .wupd_addr  (wupd_bram_addr),
    .wupd_din   (wupd_bram_din),
    .wupd_we    (wupd_bram_we),
    .wupd_dout  (wupd_bram_dout),
    .host_req   (host_bram_req),
    .host_grant (host_bram_grant),
    .host_done  (host_bram_done),
    .host_addr  (host_bram_addr),
    .host_din   (host_bram_din),
    .host_we    (host_bram_we),
    .host_dout  (host_bram_dout),
    .bram_addr  (bram_bank3_addr),
    .bram_din   (bram_bank3_din),
    .bram_dout  (bram_bank3_dout),
    .bram_we    (bram_bank3_we),
    .bram_en    (bram_bank3_en)
);

// ================================================================
// 6. MAC ENGINE
// ================================================================
mac_engine #(
    .NH          (NH),
    .NI          (NI),
    .NO          (NO),
    .T           (T),
    .W_IN_BASE   (14'h0000),
    .W_REC_BASE  (14'h0800),
    .W_OUT_BASE  (14'h4800)
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
    .score_out      (score_out),
    .score_valid    (score_valid)
);

// ================================================================
// 7. LIF ARRAY
// ================================================================
lif_array_bram #(
    .NH    (NH),
    .ALPHA (16'h00E0),
    .THETA (16'h0100)
) u_lif (
    .clk          (clk_200m),
    .rst_n        (rst_n),
    .clear_state  (1'b0),
    .lif_acc      (lif_acc),
    .lif_idx      (lif_idx),
    .lif_wen      (lif_wen),
    .lif_capture  (lif_capture),
    .lif_spikes   (lif_spikes),
    .capture_done (capture_done),
    .vm_addr      (bram_bank2_addr),
    .vm_din       (bram_bank2_din),
    .vm_dout      (bram_bank2_dout),
    .vm_we        (bram_bank2_we),
    .vm_en        (bram_bank2_en)
);

// ================================================================
// 8. OUTPUT LAYER  (per-window argmax - debug / fallback path)
//    NOTE: The embedded bank_a/bank_b overlap logic inside output_layer
//    is kept for debug; the PRIMARY voted result comes from overlap_voter.
// ================================================================
output_layer #(
    .NO (NO),
    .NH (NH)
) u_output (
    .clk            (clk_200m),
    .rst_n          (rst_n),
    .score_out      (score_out),
    .score_valid    (score_valid),
    .cmd_id         (ol_cmd_id),
    .confidence     (ol_confidence),
    .result_valid   (ol_result_valid),
    .combined_scores()
);

// ================================================================
// 9. OVERLAP VOTER
//
// Port mapping for overlap_voter_zcu104.v:
//   Inputs : clk, rst_n, score_in[NUM_CLASSES*SCORE_WIDTH-1:0],
//            score_valid
//   Outputs: pred_class[CLASS_BITS-1:0], pred_score[SUM_WIDTH-1:0],
//            pred_valid, voter_busy
//
// We feed the Q8.8 packed score bus directly from mac_engine output.
// score_valid comes directly from mac_engine (one cycle pulse).
// ================================================================
overlap_voter #(
    .NUM_CLASSES    (NO),      // 10
    .SCORE_WIDTH    (16),      // Q8.8
    .CLASS_BITS     (4),
    .SLIDING_WINDOW (0)
) u_voter (
    .clk         (clk_200m),
    .rst_n       (rst_n),
    // Score bus: NO × 16-bit Q8.8 packed flat
    .score_in    (score_packed_q88),
    .score_valid (score_valid),
    // Voted result
    .pred_class  (voter_pred_class),
    .pred_score  (voter_pred_score),
    .pred_valid  (voter_pred_valid),
    .voter_busy  (voter_busy)
);

// ================================================================
// TOP-LEVEL OUTPUT ASSIGNMENTS
// ================================================================
assign cmd_id       = voter_pred_class;
assign confidence   = voter_pred_score[15:8];  // Q9.8 → upper 8 bits = Q8.0
assign result_valid = voter_pred_valid;

// ================================================================
// NOTE: BRAM IPs are NOT instantiated here.
// In simulation the testbench provides behavioural BRAM models.
// In implementation, connect bram_bank2_* / bram_bank3_* ports
// directly to Vivado Block Design BRAM IPs via the top-level ports.
// ================================================================

endmodule
