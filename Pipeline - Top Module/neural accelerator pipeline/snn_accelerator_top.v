`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: snn_accelerator_top
// Purpose: Pure SNN Accelerator Pipeline (Inference Only)
// Chain: AER → Timestamp → Window Accum → MAC → LIF → Output → Voter
// Includes: BRAM Arbiter for weight bank access
// Excludes: Mode FSM, Display Ctrl, Training Path
//////////////////////////////////////////////////////////////////////////////////

module snn_accelerator_top (
    input  wire        clk_100m,          // 100MHz system clock
    input  wire        rst_n,             // Active-low reset
    
    // ── AER Input (from cochlea/frontend) ──
    input  wire        aer_valid,
    input  wire [23:0] aer_data,          // [23:20]=ch, [19:0]=timestamp
    
    // ── Control Gate (tie high if VAD is external/bypassed) ──
    input  wire        speech_valid,
    
    // ── Pipeline Status ──
    output wire        window_ready,      // 1-cycle pulse: 50ms window complete
    output wire        result_valid,      // 1-cycle pulse: classification ready
    output wire [3:0]  cmd_id,            // Detected command (0-9)
    output wire [7:0]  confidence,        // Q8.8 confidence score
    
    // ── BRAM Interface: Bank 3 (Weights) - Physical BRAM connection ──
    output wire [13:0] bram_bank3_addr,
    input  wire [15:0] bram_bank3_dout,
    output wire [15:0] bram_bank3_din,
    output wire        bram_bank3_we,
    output wire        bram_bank3_en,
    
    // ── BRAM Interface: Bank 2 (Neuron State V_m) - Direct connection ──
    output wire [8:0]  bram_bank2_addr,
    input  wire [15:0] bram_bank2_dout,
    output wire [15:0] bram_bank2_din,
    output wire        bram_bank2_we,
    output wire        bram_bank2_en
);

// ================================================================
// INTERNAL SIGNALS
// ================================================================

// AER Pipeline outputs
wire [3:0]  aer_ch;
wire [31:0] aer_ts;
wire        aer_ts_valid;
wire        aer_spike;
wire        aer_win_start;

// Window Accumulator interface
wire        win_open;
wire        win_ready_int;
wire        rd_ping;
wire [10:0] mac_rd_addr;
wire [7:0]  mac_rd_data;

// MAC ↔ LIF handshake
wire [15:0] lif_acc;
wire [6:0]  lif_idx;
wire        lif_wen, lif_capture;
wire [127:0] lif_spikes;
wire        capture_done;

// MAC control & scores
reg          mac_start;
wire         mac_done;
wire [319:0] score_out;   // 10 classes × 32-bit (Q16.16)
wire        score_valid;

// Overlap Voter outputs
wire [3:0]  voter_cmd;
wire [15:0] voter_conf;
wire        voter_valid, voter_busy;

// BRAM Arbiter ↔ MAC Engine
wire        mac_bram_req;
wire        mac_bram_grant;
wire        mac_bram_done;
wire [13:0] mac_bram_addr;
wire [15:0] mac_bram_din;
wire        mac_bram_we;
wire [15:0] mac_bram_dout;

// BRAM Arbiter ↔ Training modules (tied to 0 in inference-only mode)
wire        bptt_bram_req = 1'b0;
wire        bptt_bram_grant;
wire        bptt_bram_done = 1'b1;
wire [13:0] bptt_bram_addr = 14'd0;
wire [15:0] bptt_bram_din = 16'd0;
wire        bptt_bram_we = 1'b0;
wire [15:0] bptt_bram_dout;

wire        wupd_bram_req = 1'b0;
wire        wupd_bram_grant;
wire        wupd_bram_done = 1'b1;
wire [13:0] wupd_bram_addr = 14'd0;
wire [15:0] wupd_bram_din = 16'd0;
wire        wupd_bram_we = 1'b0;
wire [15:0] wupd_bram_dout;

wire        host_bram_req = 1'b0;
wire        host_bram_grant;
wire        host_bram_done = 1'b1;
wire [13:0] host_bram_addr = 14'd0;
wire [15:0] host_bram_din = 16'd0;
wire        host_bram_we = 1'b0;
wire [15:0] host_bram_dout;

// ================================================================
// 1. AER PIPELINE (Decoder + Timestamp + FIFO)
// ================================================================
aer_pipeline u_aer_pipe (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .aer_data       (aer_data),
    .aer_valid      (aer_valid),
    .channel_Id     (aer_ch),
    .timestamp      (aer_ts),
    .timestamp_valid(aer_ts_valid),
    .spike_detected (aer_spike),
    .window_start   (aer_win_start),
    .fifo_full      (),
    .fifo_empty     ()
);

// ================================================================
// 2. WINDOW ACCUMULATOR
// ================================================================
s10_window_accumulator u_win_accum (
    .clk            (clk_100m),
    .reset_n        (rst_n),
    .window_offset  (aer_ts[19:0]),   // 20-bit timestamp → bin index
    .ts_abs_valid   (aer_ts_valid),
    .spike_ch       (aer_ch),
    .speech_valid   (speech_valid),
    .window_open    (win_open),
    .window_ready   (win_ready_int),
    .rd_ping_sel    (rd_ping),
    .mac_rd_addr    (mac_rd_addr),
    .mac_rd_data    (mac_rd_data)
);
assign window_ready = win_ready_int;

// ================================================================
// 3. MINIMAL PIPELINE SEQUENCER (Triggers MAC after window_ready)
// ================================================================
reg [1:0] seq_state;
localparam SEQ_IDLE  = 2'd0;
localparam SEQ_ARM   = 2'd1;
localparam SEQ_RUN   = 2'd2;
localparam SEQ_DONE  = 2'd3;

always @(posedge clk_100m or negedge rst_n) begin
    if (!rst_n) begin
        seq_state <= SEQ_IDLE;
        mac_start <= 1'b0;
    end else begin
        mac_start <= 1'b0;
        case (seq_state)
            SEQ_IDLE: begin
                if (win_ready_int) begin
                    mac_start <= 1'b1;
                    seq_state <= SEQ_ARM;
                end
            end
            SEQ_ARM: begin
                seq_state <= SEQ_RUN; // MAC latches start on next cycle
            end
            SEQ_RUN: begin
                if (mac_done) seq_state <= SEQ_DONE;
            end
            SEQ_DONE: begin
                if (voter_valid) seq_state <= SEQ_IDLE;
            end
            default: seq_state <= SEQ_IDLE;
        endcase
    end
end

// ================================================================
// 4. BRAM ARBITER (Priority: MAC > BPTT > W_UPD > HOST)
// ================================================================
bram_arbiter #(
    .ADDR_WIDTH(14),   // 16K depth for W_rec[128×128]
    .DATA_WIDTH(16)    // Q8.8 fixed-point weights
) u_bram_arb (
    .clk        (clk_100m),
    .rst_n      (rst_n),
    
    // MAC Engine interface (ACTIVE)
    .mac_req    (mac_bram_req),
    .mac_grant  (mac_bram_grant),
    .mac_done   (mac_bram_done),
    .mac_addr   (mac_bram_addr),
    .mac_din    (mac_bram_din),
    .mac_we     (mac_bram_we),
    .mac_dout   (mac_bram_dout),
    
    // BPTT interface (INACTIVE - tied to 0)
    .bptt_req   (bptt_bram_req),
    .bptt_grant (bptt_bram_grant),
    .bptt_done  (bptt_bram_done),
    .bptt_addr  (bptt_bram_addr),
    .bptt_din   (bptt_bram_din),
    .bptt_we    (bptt_bram_we),
    .bptt_dout  (bptt_bram_dout),
    
    // Weight Updater interface (INACTIVE - tied to 0)
    .wupd_req   (wupd_bram_req),
    .wupd_grant (wupd_bram_grant),
    .wupd_done  (wupd_bram_done),
    .wupd_addr  (wupd_bram_addr),
    .wupd_din   (wupd_bram_din),
    .wupd_we    (wupd_bram_we),
    .wupd_dout  (wupd_bram_dout),
    
    // HOST/UART interface (INACTIVE - tied to 0)
    .host_req   (host_bram_req),
    .host_grant (host_bram_grant),
    .host_done  (host_bram_done),
    .host_addr  (host_bram_addr),
    .host_din   (host_bram_din),
    .host_we    (host_bram_we),
    .host_dout  (host_bram_dout),
    
    // Physical BRAM Bank 3 connection
    .bram_addr  (bram_bank3_addr),
    .bram_din   (bram_bank3_din),
    .bram_dout  (bram_bank3_dout),
    .bram_we    (bram_bank3_we),
    .bram_en    (bram_bank3_en)
);

// ================================================================
// 5. MAC ENGINE + LIF ARRAY (Tightly Coupled)
// ================================================================
mac_engine #(
    .NH(128), .NI(16), .NO(10), .T(50), .N_PE(16),
    .W_IN_BASE(16'h0000), .W_REC_BASE(16'h1000), .W_OUT_BASE(16'h9000)
) u_mac (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .mac_start      (mac_start),
    .mac_done       (mac_done),
    
    // BRAM interface via arbiter
    .w_raddr_flat   (mac_bram_addr),    // ← from arbiter
    .w_rdata_flat   ({mac_bram_dout, mac_bram_dout, mac_bram_dout, mac_bram_dout}), // 64-bit expansion
    .w_ren          (mac_bram_grant),   // ← grant acts as enable
    
    // LIF Array interface
    .lif_acc        (lif_acc),
    .lif_idx        (lif_idx),
    .lif_wen        (lif_wen),
    .lif_capture    (lif_capture),
    .lif_spikes     (lif_spikes),
    
    // Output scores
    .score_out      (score_out),
    .score_valid    (score_valid)
);

lif_array #(
    .NH(128), .ALPHA(16'h00E0), .THETA(16'h0100)
) u_lif (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .clear_state    (1'b0),           // Never clear during inference
    .lif_acc        (lif_acc),
    .lif_idx        (lif_idx),
    .lif_wen        (lif_wen),
    .lif_capture    (lif_capture),
    .lif_spikes     (lif_spikes),
    .capture_done   (capture_done)
);

// Neuron State BRAM (Bank 2) - Direct connection (no contention in inference)
assign bram_bank2_addr = lif_idx;
assign bram_bank2_din  = lif_acc;         // V_m update data
assign bram_bank2_we   = lif_wen;
assign bram_bank2_en   = lif_wen || lif_capture;

// ================================================================
// 6. OUTPUT LAYER → OVERLAP VOTER
// ================================================================
output_layer #(
    .NO(10), .NH(128)
) u_output (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .score_out      (score_out),
    .score_valid    (score_valid),
    .cmd_id         (),               // Handled by voter
    .confidence     (),               // Handled by voter
    .result_valid   (),               // Handled by voter
    .combined_scores()
);

overlap_voter #(
    .NUM_CLASSES(10), .SCORE_WIDTH(16), .SUM_WIDTH(17),
    .CLASS_BITS(4), .SLIDING_WINDOW(0)
) u_voter (
    .clk            (clk_100m),
    .rst_n          (rst_n),
    .score_in       (score_out[159:0]), // Lower 160 bits = 10×16b scores
    .score_valid    (score_valid),
    .pred_class     (cmd_id),
    .pred_score     (voter_conf),
    .pred_valid     (result_valid),
    .voter_busy     (voter_busy)
);
assign confidence = voter_conf[15:8]; // Q8.8 → upper 8 bits

endmodule
