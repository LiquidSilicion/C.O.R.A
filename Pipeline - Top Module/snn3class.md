`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module: snn_top_with_rom  (v7 - LED display output added)
//
// CHANGES vs v6:
//   - Added output port: led[3:0]  (drives ZCU104 GPIO LEDs DS50-DS53)
//   - Instantiates cmd_led_display, wired to overlap_voter's pred_class /
//     pred_valid outputs (50 MHz domain - no extra CDC needed).
//   - All other logic is unchanged from v6.
//////////////////////////////////////////////////////////////////////////////////
module snn_top_with_rom #(
    parameter MEM_DEPTH        = 15000,
    parameter ADDR_WIDTH       = 14,
    parameter SAMPLE_EN_PERIOD = 6250,   // 16 kHz @ 100 MHz
    parameter NUM_LOOPS        = 2       // AER encoder replays = number of windows
)(
    input  wire clk_125_p,
    input  wire clk_125_n,
    input  wire rst,
    // ── NEW ── ZCU104 on-board LEDs (DS50-DS53)
    output wire [1:0] led
);

    //===========================================================================
    // Clock Generation: 125 MHz → 100 MHz → 50 MHz
    //===========================================================================
    wire encoder_done;
    wire clk_bufg, clk, clk1, clk_50;
    IBUFDS ibufds_inst (.I(clk_125_p), .IB(clk_125_n), .O(clk_bufg));
    BUFG   bufg_inst   (.I(clk_bufg), .O(clk1));
    wire locked;
      clk_wiz_0 instance_name
   (
    // Clock out ports
    .clk_out1(clk),     // output clk_out1
    .clk_out2(clk_50),     // output clk_out2
    // Status and control signals
    .locked(locked),       // output locked
   // Clock in ports
    .clk_in1(clk1)      // input clk_in1
);
   

    //===========================================================================
    // Signals
    //===========================================================================
    wire [3:0]  channel_Id;
    wire [31:0] timestamp, window_start_ts;
    wire [19:0] window_offset_wire;
    wire        timestamp_valid, spike_detected, fifo_empty, sample_en;
    wire        speech_valid = 1'b1;

    wire        sync_valid;
    wire [3:0]  sync_ch;
    wire [19:0] sync_offset;
    wire [10:0] mac_rd_addr;
    wire [7:0]  mac_rd_data;
    wire        rd_ping_sel;
    wire        mac_done;
    wire        window_ready_slow;

    //===========================================================================
    // FIX-C: Sample Enable - stops when encoder_done (after NUM_LOOPS passes)
    //===========================================================================
    reg [13:0] sample_cnt;
    reg        sample_en_reg;
    assign sample_en = sample_en_reg;

    always @(posedge clk) begin
        if (rst) begin
            sample_cnt    <= 14'd0;
            sample_en_reg <= 1'b0;
        end else if (!encoder_done) begin
            if (sample_cnt == SAMPLE_EN_PERIOD - 1) begin
                sample_en_reg <= 1'b1;
                sample_cnt    <= 14'd0;
            end else begin
                sample_en_reg <= 1'b0;
                sample_cnt    <= sample_cnt + 1'b1;
            end
        end else begin
            sample_en_reg <= 1'b0;
            sample_cnt    <= 14'd0;
        end
    end

    //===========================================================================
    // FIX-D: window_open_pulse CDC (50 MHz → 100 MHz)
    //===========================================================================
    reg win_rdy_sync1, win_rdy_sync2, win_rdy_sync3;
    always @(posedge clk) begin
        if (rst) begin
            win_rdy_sync1 <= 1'b0;
            win_rdy_sync2 <= 1'b0;
            win_rdy_sync3 <= 1'b0;
        end else begin
            win_rdy_sync1 <= window_ready_slow;
            win_rdy_sync2 <= win_rdy_sync1;
            win_rdy_sync3 <= win_rdy_sync2;
        end
    end
    wire window_open_pulse = win_rdy_sync2 & ~win_rdy_sync3;

    //===========================================================================
    // FIX-A: AER Pipeline with NUM_LOOPS forwarded to aer_encoder_model
    //===========================================================================
    aer_pipeline #(
        .MEM_DEPTH  (MEM_DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .NUM_LOOPS  (NUM_LOOPS)
    ) u_aer_pipe (
        .clk             (clk),
        .rst             (rst),
        .rom_en          (sample_en),
        .window_open     (window_open_pulse),
        .channel_Id      (channel_Id),
        .timestamp       (timestamp),
        .timestamp_valid (timestamp_valid),
        .spike_detected  (spike_detected),
        .window_start    (window_start_ts),
        .window_offset   (window_offset_wire),
        .fifo_full       (),
        .fifo_empty      (fifo_empty),
        .rom_done        (encoder_done)
    );

    //===========================================================================
    // Window Accumulator (50 MHz)
    //===========================================================================
    s10_window_accumulator u_win_acc (
    .clk          (clk_50),
    .rst          (rst),
    .window_offset(window_offset_wire),
    .ts_abs_valid (timestamp_valid),
    .spike_ch     (channel_Id),
    .speech_valid (speech_valid),
    .window_open  (),
    .window_ready (window_ready_slow),
    .rd_ping_sel  (rd_ping_sel),
    .mac_rd_addr  (mac_rd_addr),
    .mac_done     (mac_done),
    .mac_rd_data  (mac_rd_data)
);
    //===========================================================================
    // mac_start: 1-cycle delay ensures rd_ping_sel stable when MAC samples it
    //===========================================================================
    reg mac_start_r;
    always @(posedge clk_50) begin
        if (rst) mac_start_r <= 1'b0;
        else     mac_start_r <= window_ready_slow;
    end
    wire mac_start = mac_start_r;

    //===========================================================================
    // MAC Engine + Weight Router + LIF Array (50 MHz)
    //===========================================================================
    wire         score_valid_mac;
    wire [95:0] score_out_mac;
    wire [255:0] mac_w_raddr, mac_w_rdata;
    wire         mac_w_ren;
    wire [15:0]  mac_lif_acc;
    wire [6:0]   mac_lif_idx;
    wire         mac_lif_wen, mac_lif_capture;
    wire [127:0] mac_lif_spikes;
    wire         lif_capture_done;

    mac_engine #(
        .NH(128), .NI(16), .NO(3), .T(50), .N_PE(16),
        .W_IN_BASE (16'h0000),
        .W_REC_BASE(16'h1000),
        .W_OUT_BASE(16'h9000)
    ) u_mac (
        .clk          (clk_50), .rst(rst),
        .mac_start    (mac_start),
        .capture_done (lif_capture_done),
        .rd_ping_sel  (rd_ping_sel),
        .mac_rd_addr  (mac_rd_addr),
        .mac_rd_data  (mac_rd_data),
        .mac_done     (mac_done),
        .score_out    (score_out_mac),
        .score_valid  (score_valid_mac),
        .lif_acc      (mac_lif_acc),   .lif_idx(mac_lif_idx),
        .lif_wen      (mac_lif_wen),   .lif_capture(mac_lif_capture),
        .lif_spikes   (mac_lif_spikes),
        .w_raddr_flat (mac_w_raddr),   .w_rdata_flat(mac_w_rdata),
        .w_ren        (mac_w_ren),
        .x_raddr(), .x_ren(), .x_rdata(8'd0)
    );

    weight_router #(.N_PE(16)) u_w_router (
        .clk(clk_50), .rst(rst),
        .ren(mac_w_ren), .raddr_flat(mac_w_raddr), .rdata_flat(mac_w_rdata)
    );

    lif_array #(.NH(128), .ALPHA(16'h00E0), .THETA(16'h0100)) u_lif (
        .clk(clk_50), .rst(rst), .clear_state(1'b0),
        .lif_acc(mac_lif_acc), .lif_idx(mac_lif_idx), .lif_wen(mac_lif_wen),
        .lif_capture(mac_lif_capture),
        .lif_spikes(mac_lif_spikes),
        .capture_done(lif_capture_done)
    );

    //===========================================================================
    // Windows-done counter (50 MHz) - monitoring only
    //===========================================================================
    reg [1:0] windows_mac_done;
    always @(posedge clk_50) begin
        if (rst)
            windows_mac_done <= 2'd0;
        else if (mac_done && windows_mac_done < 2'd2)
            windows_mac_done <= windows_mac_done + 2'd1;
    end

    reg win_done_f1, win_done_f2;
    always @(posedge clk) begin
        if (rst) begin win_done_f1 <= 1'b0; win_done_f2 <= 1'b0; end
        else     begin win_done_f1 <= windows_mac_done[1]; win_done_f2 <= win_done_f1; end
    end
    wire two_windows_done = win_done_f2;

    //===========================================================================
    // Overlap Voter (50 MHz)
    //===========================================================================
    wire         score_valid_final;
    wire [3:0]   pred_class;
    wire [32:0]  pred_score;
    wire         voter_busy;

    overlap_voter #(
        .NUM_CLASSES   (3),
        .SCORE_WIDTH   (32),
        .SUM_WIDTH     (33),
        .CLASS_BITS    (4),
        .SLIDING_WINDOW(0)
    ) u_overlap_voter (
        .clk        (clk_50),
        .rst        (rst),
        .score_in   (score_out_mac),
        .score_valid(score_valid_mac),
        .pred_class (pred_class),
        .pred_score (pred_score),
        .pred_valid (score_valid_final),
        .voter_busy (voter_busy)
    );

    //===========================================================================
    // ── NEW ── LED Display (50 MHz - same domain as voter, no CDC needed)
    //
    // pred_class[3:0] → latched on pred_valid pulse → shown on LEDs DS50-DS53
    // LED blinks blank for 80 ms on each new prediction to signal update.
    //===========================================================================
    led_out u_led (
        .clk        (clk_50),
        .rst        (rst),
        .pred_class (pred_class),
        .pred_valid (score_valid_final),
        .led        (led)
    );

endmodule
`default_nettype wire



`timescale 1ns / 1ps
`default_nettype none

module aer_pipeline #(
    parameter MEM_DEPTH  = 15000,
    parameter ADDR_WIDTH = 14,
    parameter NUM_LOOPS  = 2     // FIX-A: replay file this many times
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        rom_en,
    input  wire        window_open,
    output wire [3:0]  channel_Id,
    output wire [31:0] timestamp,
    output wire        timestamp_valid,
    output wire        spike_detected,
    output wire [31:0] window_start,
    output wire [19:0] window_offset,
    output wire        fifo_full,
    output wire        fifo_empty,
    output wire        rom_done
);

wire [23:0] encoder_data, fifo_dout;
wire        encoder_valid, fifo_rd_en, raw_ts_valid;
reg         fifo_rd_valid;
wire [19:0] raw_ts;
wire        encoder_done;

assign fifo_rd_en = !fifo_empty;

always @(posedge clk) begin
    if (rst) fifo_rd_valid <= 1'b0;
    else     fifo_rd_valid <= fifo_rd_en;
end

// FIX-A: Pass NUM_LOOPS so encoder replays NUM_LOOPS windows
aer_encoder_model #(
    .MEM_FILE  ("aer_input.mem"),
    .MEM_DEPTH (MEM_DEPTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .NUM_LOOPS (NUM_LOOPS)
) u_encoder (
    .clk      (clk),
    .rst      (rst),
    .sample_en(rom_en),
    .aer_data (encoder_data),
    .aer_valid(encoder_valid),
    .aer_ready(!fifo_full),
    .done     (encoder_done)
);

fifo #(
    .DATA_WIDTH(24),
    .DEPTH     (64),
    .ADDR_WIDTH(6)
) u_fifo (
    .clk  (clk), .rst(rst),
    .wr_en(encoder_valid), .rd_en(fifo_rd_en),
    .din  (encoder_data),  .dout(fifo_dout),
    .full (fifo_full),     .empty(fifo_empty)
);

input_from_aer u_decoder (
    .clk          (clk), .rst(rst),
    .in           (fifo_dout),
    .aer_valid    (fifo_rd_valid),
    .channel_Id   (channel_Id),
    .timestamp    (raw_ts),
    .timestamp_valid(raw_ts_valid),
    .spike_detected (spike_detected)
);

wire [19:0] window_offset_internal;
timestamp_manager u_ts_mgr (
    .clk         (clk), .rst(rst),
    .timestamp   (raw_ts),
    .ts_valid    (raw_ts_valid),
    .window_open (window_open),
    .ts_abs      (timestamp),
    .ts_abs_valid(timestamp_valid),
    .window_start(window_start),
    .window_offset(window_offset_internal)
);

assign window_offset = window_offset_internal;
assign rom_done      = encoder_done;

endmodule



`timescale 1ns / 1ps
`default_nettype none

module aer_encoder_model #(
    parameter MEM_FILE   = "aer_input.mem",
    parameter MEM_DEPTH  = 15000,
    parameter ADDR_WIDTH = 14,
    parameter NUM_LOOPS  = 2        // replay file this many times
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_en,
    output reg  [23:0] aer_data,
    output reg         aer_valid,
    input  wire        aer_ready,
    output wire        done
);

reg [23:0]       spike_events [0:MEM_DEPTH-1];
reg [ADDR_WIDTH-1:0] event_idx;
reg [2:0]        valid_hold_cnt;
reg [2:0]        loop_count;    // how many full passes completed
integer init_i;

initial begin
    $readmemh(MEM_FILE, spike_events);
    for (init_i = 0; init_i < MEM_DEPTH; init_i = init_i + 1) begin
        if (spike_events[init_i] === 24'bx)
            spike_events[init_i] = 24'd0;
    end
    event_idx      = 0;
    loop_count     = 3'd0;
    aer_data       = 24'd0;
    aer_valid      = 1'b0;
    valid_hold_cnt = 3'd0;
end

// done only after NUM_LOOPS complete passes
assign done = (loop_count >= NUM_LOOPS[2:0]);

always @(posedge clk) begin
    if (rst) begin
        aer_data        <= 24'd0;
        aer_valid       <= 1'b0;
        event_idx       <= 0;
        loop_count      <= 3'd0;
        valid_hold_cnt  <= 3'd0;
    end else begin
        // Drain hold counter
        if (valid_hold_cnt > 0) begin
            valid_hold_cnt  <= valid_hold_cnt - 1'b1;
            if (valid_hold_cnt == 3'd1)
                aer_valid  <= 1'b0;
        end else if (sample_en && aer_ready && !done) begin
            aer_data        <= spike_events[event_idx];
            aer_valid       <= 1'b1;
            valid_hold_cnt  <= 3'd3;

            // Advance; wrap at end of each loop
            if (event_idx == MEM_DEPTH - 1) begin
                event_idx   <= 0;
                loop_count  <= loop_count + 3'd1;
            end else begin
                event_idx  <= event_idx + 1'b1;
            end
        end
    end
end

endmodule



`timescale 1ns / 1ps
`default_nettype none

module fifo #(
    parameter DATA_WIDTH = 24,
    parameter DEPTH = 64,
    parameter ADDR_WIDTH = 6
)(
    // FIX: Add explicit 'wire' type to all input ports
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   wr_en,
    input  wire                   rd_en,
    input  wire [DATA_WIDTH-1:0]  din,
    
    // dout is assigned in always block → keep 'reg'
    output reg  [DATA_WIDTH-1:0]  dout,
    
    // FIX: full/empty use continuous assignment → must be 'wire'
    output wire                   full,
    output wire                   empty
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;
    
    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];
    
    integer init_i;
    
    initial begin
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
            mem[init_i] = 24'd0;
    end

    // Write pointer logic
    always @(posedge clk) begin
        if (rst) 
            wr_ptr <= 0;
        else if (wr_en && !full) begin  // !full OK: full is 1-bit wire
            mem[wr_addr] <= din;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Read pointer + data output logic
    always @(posedge clk) begin
        if (rst) begin 
            rd_ptr <= 0; 
            dout <= 0; 
        end
        else if (rd_en && !empty) begin  // !empty OK: empty is 1-bit wire
            dout <= mem[rd_addr];
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // Continuous assignments to wire-type outputs
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr == rd_ptr + DEPTH);

endmodule

`default_nettype wire



`timescale 1ns / 1ps
module input_from_aer (
    input               clk,
    input               rst,
    input  [23:0]       in,
    input               aer_valid,
    output reg          spike_detected,
    output reg [3:0]    channel_Id,
    output reg [19:0]   timestamp,
    output reg          timestamp_valid
);
    reg [23:0] pipe0, pipe1, pipe2;
    reg        valid0, valid1, valid2;

    always @(posedge clk) begin
        if (rst) begin
            pipe0 <= 24'd0; pipe1 <= 24'd0; pipe2 <= 24'd0;
            valid0 <= 1'b0; valid1 <= 1'b0; valid2 <= 1'b0;
            channel_Id <= 4'd0; timestamp <= 20'd0;
            spike_detected <= 1'b0; timestamp_valid <= 1'b0;
        end else begin
            if (aer_valid) begin pipe0 <= in; valid0 <= 1'b1; end
            else valid0 <= 1'b0;
            pipe1 <= pipe0; valid1 <= valid0;
            pipe2 <= pipe1; valid2 <= valid1;
            if (valid2) begin
                channel_Id <= pipe2[23:20];
                timestamp <= pipe2[19:0];
                timestamp_valid <= 1'b1;
                spike_detected <= 1'b1;
            end else begin
                timestamp_valid <= 1'b0;
                spike_detected <= 1'b0;
            end
        end
    end
endmodule


`timescale 1ns / 1ps
module timestamp_manager(
    input  wire        clk,
    input  wire        rst,
    input  wire [19:0] timestamp,
    input  wire        ts_valid,
    input  wire        window_open,
    output reg  [31:0] ts_abs,
    output reg         ts_abs_valid,
    output reg  [31:0] window_start,
    output reg  [19:0] window_offset
);
    reg [19:0] ts_prev;
    reg [11:0] rollover_count;
    wire [31:0] ts_abs_comb;
    assign ts_abs_comb = {rollover_count, timestamp};
    wire [31:0] offset_full;
    assign offset_full = ts_abs_comb - window_start;
    wire rollover_detected;
    assign rollover_detected = ts_valid && (ts_prev > timestamp) && ((ts_prev - timestamp) > 20'h80000);

    always @(posedge clk) begin
        if (rst) begin rollover_count <= 12'd0; ts_prev <= 20'd0; end
        else if (ts_valid) begin
            if (rollover_detected) rollover_count <= rollover_count + 12'd1;
            ts_prev <= timestamp;
        end
    end

    always @(posedge clk) begin
        if (rst) begin ts_abs <= 32'd0; ts_abs_valid <= 1'b0; end
        else begin
            ts_abs_valid <= ts_valid;
            if (ts_valid) begin
                if (rollover_detected) ts_abs <= {rollover_count + 12'd1, timestamp};
                else ts_abs <= {rollover_count, timestamp};
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin window_start <= 32'd0; window_offset <= 20'd0; end
        else begin
            if (window_open) window_start <= ts_abs_comb;
            if (ts_valid) begin
                if (offset_full[31:20] != 12'd0) window_offset <= 20'hFFFFF;
                else window_offset <= offset_full[19:0];
            end
        end
    end
endmodule



`timescale 1ns / 1ps
`default_nettype none

module s10_window_accumulator (
    input  wire          clk,
    input  wire          rst,
    input  wire [19:0]   window_offset,
    input  wire          ts_abs_valid,
    input  wire [3:0]    spike_ch,
    input  wire          speech_valid,
    output reg           window_open,
    output reg           window_ready,
    output reg           rd_ping_sel,
    input  wire [10:0]   mac_rd_addr,
    input  wire          mac_done,
    output wire [7:0]    mac_rd_data
);

localparam EMIT_BIN = 6'd49;
localparam OVL_OFF  = 6'd25;
localparam MAX_CNT  = 8'hFF;
localparam CLR_MAX  = 11'd1599;
localparam CLEAR_TIMEOUT = 20'd250_000;
localparam GATED = 2'd0, ACCUM = 2'd1, EMIT = 2'd2, CLEAR = 2'd3;
localparam PH_WR_A = 2'd0, PH_RD_B = 2'd1, PH_WR_B = 2'd2;

reg [1:0] state;
reg       ping_sel;
reg       clear_ping;
reg       mac_done_seen;  // FIX: latch for mac_done

wire [5:0] bin_a;
assign bin_a = window_offset[11:6];
wire bin_valid;
assign bin_valid = (bin_a <= EMIT_BIN);
wire do_emit;
assign do_emit = ts_abs_valid && (bin_a == EMIT_BIN) && speech_valid;
wire bin_b_en;
assign bin_b_en = (bin_a >= OVL_OFF);
wire [5:0] bin_b;
assign bin_b = bin_a - OVL_OFF;

reg        bram_ena;
reg        bram_wea;
reg [10:0] bram_addra;
reg  [7:0] bram_dina;
wire [7:0] bram_douta;

window_acc_bram u_bram (
    .clka (clk), .rst(rst), .ena(bram_ena), .wea(bram_wea),
    .addra(bram_addra), .dina(bram_dina), .douta(bram_douta),
    .clkb (clk), .enb(1'b1), .web(1'b0),
    .addrb(mac_rd_addr), .dinb(8'd0), .doutb(mac_rd_data)
);

// Pipeline registers
reg        s0_valid;
reg [10:0] s0_addr_a;
reg        s0_do_b;
reg [10:0] s0_addr_b;
reg        s1_valid;
reg [1:0]  s1_ph;
reg [10:0] s1_addr_a;
reg  [7:0] s1_val_a;
reg        s1_do_b;
reg [10:0] s1_addr_b;

// Shadow register for sticky forwarding
reg [10:0] shd_addr;
reg  [7:0] shd_val;
reg        shd_valid;
wire use_shadow;
assign use_shadow = shd_valid && (s0_addr_a == shd_addr);
wire [7:0] cur_val;
assign cur_val = use_shadow ? shd_val : bram_douta;
wire [7:0] inc_a;
assign inc_a = (cur_val == MAX_CNT) ? MAX_CNT : cur_val + 8'd1;
wire [7:0] inc_b;
assign inc_b = (bram_douta == MAX_CNT) ? MAX_CNT : bram_douta + 8'd1;
wire pipe_busy;
assign pipe_busy = s0_valid || s1_valid;

// Clear counters
reg [10:0] clr_cnt;
reg [3:0]  clr_ch;
reg [5:0]  clr_bin;
reg [19:0] clear_timeout;

always @(posedge clk) begin
    if (rst) begin
        state          <= GATED;
        ping_sel       <= 1'b0;
        rd_ping_sel    <= 1'b0;
        clear_ping     <= 1'b0;
        window_ready   <= 1'b0;
        window_open    <= 1'b0;
        mac_done_seen  <= 1'b0;
        bram_ena       <= 1'b0;
        bram_wea       <= 1'b0;
        bram_addra     <= 11'd0;
        bram_dina      <= 8'd0;
        s0_valid       <= 1'b0;
        s0_addr_a      <= 11'd0;
        s0_do_b        <= 1'b0;
        s0_addr_b      <= 11'd0;
        s1_valid       <= 1'b0;
        s1_ph          <= 2'd0;
        s1_addr_a      <= 11'd0;
        s1_val_a       <= 8'd0;
        s1_do_b        <= 1'b0;
        s1_addr_b      <= 11'd0;
        shd_addr       <= 11'd0;
        shd_val        <= 8'd0;
        shd_valid      <= 1'b0;
        clr_cnt        <= 11'd0;
        clr_ch         <= 4'd0;
        clr_bin        <= 6'd0;
        clear_timeout  <= 20'd0;
    end else begin
        // Default deassertions
        window_ready  <= 1'b0;
        window_open   <= 1'b0;
        bram_wea      <= 1'b0;
        bram_ena      <= 1'b0;

        // FIX: latch mac_done whenever it arrives while in CLEAR state
        if (state == CLEAR && mac_done)
            mac_done_seen  <= 1'b0;

        case (state)
            GATED: begin
                if (speech_valid) state  <= ACCUM;
            end

            ACCUM: begin
                // ==== Stage-1 write-back FSM ====
                if (s1_valid) begin
                    case (s1_ph)
                        PH_WR_A : begin
                            bram_ena    <= 1'b1;
                            bram_wea    <= 1'b1;
                            bram_addra  <= s1_addr_a;
                            bram_dina   <= s1_val_a;
                            shd_addr    <= s1_addr_a;
                            shd_val     <= s1_val_a;
                            shd_valid   <= 1'b1;
                            if (s1_do_b)
                                s1_ph  <= PH_RD_B;
                            else begin
                                s1_valid   <= 1'b0;
                                shd_valid  <= 1'b0;
                            end
                        end
                        PH_RD_B: begin
                            bram_ena    <= 1'b1;
                            bram_wea    <= 1'b0;
                            bram_addra  <= s1_addr_b;
                            s1_ph       <= PH_WR_B;
                        end
                        PH_WR_B: begin
                            bram_ena    <= 1'b1;
                            bram_wea    <= 1'b1;
                            bram_addra  <= s1_addr_b;
                            bram_dina   <= inc_b;
                            shd_addr    <= s1_addr_b;
                            shd_val     <= inc_b;
                            s1_valid    <= 1'b0;
                            s1_ph       <= PH_WR_A;
                            shd_valid   <= 1'b0;
                        end
                        default: begin
                            s1_valid   <= 1'b0;
                            shd_valid  <= 1'b0;
                        end
                    endcase
                end

                // ==== S0 → S1 ====
                if (s0_valid && !s1_valid) begin
                    s1_valid   <= 1'b1;
                    s1_ph      <= PH_WR_A;
                    s1_addr_a  <= s0_addr_a;
                    s1_val_a   <= inc_a;
                    s1_do_b    <= s0_do_b;
                    s1_addr_b  <= s0_addr_b;
                    s0_valid   <= 1'b0;
                end

                // ==== Accept new spike ====
                if (ts_abs_valid && bin_valid && !do_emit && !pipe_busy) begin
                    bram_ena    <= 1'b1;
                    bram_wea    <= 1'b0;
                    bram_addra  <= {ping_sel, spike_ch, bin_a};
                    s0_valid    <= 1'b1;
                    s0_addr_a   <= {ping_sel, spike_ch, bin_a};
                    s0_do_b     <= bin_b_en;
                    s0_addr_b   <= {~ping_sel, spike_ch, bin_b};
                end

                // ==== State transitions ====
                if (!speech_valid) begin
                    s0_valid   <= 1'b0;
                    s1_valid   <= 1'b0;
                    s1_ph      <= 2'd0;
                    shd_valid  <= 1'b0;
                    state      <= GATED;
                end else if (do_emit) begin
                    state  <= EMIT;
                end
            end

            EMIT: begin
                window_ready   <= 1'b1;
                window_open    <= 1'b1;
                rd_ping_sel    <= ping_sel;
                clear_ping     <= ping_sel;
                ping_sel       <= ~ping_sel;
                clr_cnt        <= 11'd0;
                clr_ch         <= 4'd0;
                clr_bin        <= 6'd0;
                clear_timeout  <= 20'd0;
                mac_done_seen  <= 1'b0;
                s0_valid       <= 1'b0;
                s1_valid       <= 1'b0;
                s1_ph          <= 2'd0;
                shd_valid      <= 1'b0;
                state          <= CLEAR;
            end

            CLEAR: begin
                bram_ena       <= 1'b1;
                clear_timeout  <= clear_timeout + 20'd1;

                // FIX: use mac_done_seen (latched) instead of mac_done (pulse)
                if (mac_done_seen || (clear_timeout >= CLEAR_TIMEOUT)) begin
                    bram_wea    <= 1'b1;
                    bram_addra  <= {clear_ping, clr_ch, clr_bin};
                    bram_dina   <= 8'd0;
                    if (clr_cnt[0]) begin
                        if (clr_bin == 6'd49) begin
                            clr_bin  <= 6'd0;
                            clr_ch   <= clr_ch + 4'd1;
                        end else begin
                            clr_bin  <= clr_bin + 6'd1;
                        end
                    end
                    clr_cnt  <= clr_cnt + 11'd1;
                    if (clr_cnt == CLR_MAX) begin
                        mac_done_seen  <= 1'b0;
                        clear_timeout  <= 20'd0;
                        state          <= ACCUM;
                    end
                end else begin
                    bram_wea  <= 1'b0;
                end
            end

            default: state  <= GATED;
        endcase
    end
end

endmodule



`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module: window_acc_bram
// Fix: Explicitly declared all inputs as 'wire' to resolve VRFC 10-3236 error.
// The error occurred because Vivado interpreted the ports as 'reg' types,
// which cannot be driven by continuous assignments (port connections).
//////////////////////////////////////////////////////////////////////////////////
module window_acc_bram (
    input  wire             clka,
    input  wire             rst,
    input  wire             ena,
    input  wire             wea,
    input  wire  [10:0]     addra,
    input  wire  [7:0]      dina,
    output reg   [7:0]      douta,
    input  wire             clkb,
    input  wire             enb,
    input  wire             web,
    input  wire  [10:0]     addrb,
    input  wire  [7:0]      dinb,
    output reg   [7:0]      doutb
);
    // Infer Block RAM using Xilinx attribute
    (* ram_style = "block" *) reg [7:0] mem [0:2047];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < 2048; init_i = init_i + 1)
            mem[init_i] = 8'd0;
    end

    // Port A: Write/Read for Accumulation
    always @(posedge clka) begin
        if (rst) begin
            douta <= 8'd0;
        end else if (ena) begin
            if (wea) mem[addra] <= dina;
            douta <= mem[addra];
        end
    end

    // Port B: Read-only for MAC Engine
    always @(posedge clkb) begin
        if (rst) begin
            doutb <= 8'd0;
        end else if (enb) begin
            if (web) mem[addrb] <= dinb;
            doutb <= mem[addrb];
        end
    end
endmodule
`default_nettype wire


`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module: mac_engine
//
// FIXES APPLIED:
// 1. Address Generation (Bug A):
//    Changed row index from 'group_cnt' to 'group_cnt * N_PE + k' in loops.
//    This ensures each PE (k=0..15) reads the weights for its specific neuron
//    (0..127) instead of all PEs reading the same address.
//
// 2. Output Layer Stride (Bug B):
//    Changed stride for W_OUT from NH (128) to NO (10).
//    W_OUT is stored as [neuron][class], so the inner dimension size is NO.
//
// 3. Pipeline Alignment:
//    Ensured all waddr calls use the correct stride and row indices.
//////////////////////////////////////////////////////////////////////////////////
module mac_engine #(
    parameter NH         = 128,
    parameter NI         = 16,
    parameter NO         = 3,
    parameter T          = 50,          // time steps per window
    parameter N_PE       = 16,
    parameter W_IN_BASE  = 16'h0000,
    parameter W_REC_BASE = 16'h1000,
    parameter W_OUT_BASE = 16'h9000
)(
    input  wire clk,
    input  wire rst,
    input  wire mac_start,
    input  wire capture_done,
    input  wire rd_ping_sel,
    output reg  [10:0] mac_rd_addr,
    input  wire [7:0]  mac_rd_data,
    output reg  mac_done,
    output reg  [15:0] x_raddr,
    output reg  x_ren,
    input  wire [7:0]  x_rdata,
    output reg  [N_PE*16-1:0] w_raddr_flat,
    input  wire [N_PE*16-1:0] w_rdata_flat,
    output reg  w_ren,
    output reg  [15:0] lif_acc,
    output reg  [6:0]  lif_idx,
    output reg  lif_wen,
    output reg  lif_capture,
    input  wire [NH-1:0] lif_spikes,
    output reg  [NO*32-1:0] score_out,
    output reg  score_valid
);
    localparam GROUPS = NH / N_PE;   // 128/16 = 8
    localparam [3:0] S_IDLE    = 4'd0,
                     S_LOAD_X  = 4'd1,
                     S_W_IN    = 4'd2,
                     S_W_REC   = 4'd3,
                     S_LIF_UPD = 4'd4,
                     S_W_OUT   = 4'd5,
                     S_NEXT_T  = 4'd6,
                     S_DONE    = 4'd7;

    localparam [1:0] PH_WIN  = 2'd0,
                     PH_WREC = 2'd1,
                     PH_WOUT = 2'd2;

    reg [3:0]  state;
    reg [5:0]  t_cnt;
    reg [7:0]  group_cnt, col_cnt, lif_cnt;
    reg [31:0] acc   [0:NH-1];
    reg [31:0] score [0:NO-1];
    reg [NH-1:0] s_prev;

    // Capture rd_ping_sel when mac_start fires so it stays stable
    reg ping_captured;

    // 1-cycle delay to match BRAM read latency
    reg [7:0] mac_rd_data_s1;

    reg        p0_en,    p1_en;
    reg [ 1:0]  p0_ph,    p1_ph;
    reg [7:0]  p0_group, p1_group;
    reg [7:0]  p0_col,   p1_col;
    reg [15:0] p0_wdata [0:N_PE-1];
    reg [15:0] p1_wdata [0:N_PE-1];
    reg [15:0] p0_xop   [0:N_PE-1];
    reg [15:0] p1_xop   [0:N_PE-1];

    wire signed [31:0] mac_res [0:N_PE-1];

    genvar gv;
    generate
        for (gv = 0; gv < N_PE; gv = gv + 1) begin : gen_mac
            assign mac_res[gv] = $signed(p1_wdata[gv]) * $signed(p1_xop[gv]);
        end
    endgenerate

    wire signed [31:0] pe_sum [0:N_PE];
    assign pe_sum[0] = 32'sd0;
    generate
        for (gv = 0; gv < N_PE; gv = gv + 1) begin : gen_pesum
            assign pe_sum[gv+1] = pe_sum[gv] + mac_res[gv];
        end
    endgenerate
    wire signed [31:0] pe_total = pe_sum[N_PE];

    integer pi, k, ri;

    always @(*) begin
        for (pi = 0; pi < NO; pi = pi + 1)
            score_out[pi*32 +: 32] = score[pi];
    end

    // Weight address: base + row*stride + col
    function [15:0] waddr;
        input [15:0] base;
        input [7:0]  row, col, stride;
        begin
            waddr = base + row * stride + col;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state           <= S_IDLE;
            t_cnt           <= 6'd0;
            group_cnt       <= 8'd0;
            col_cnt         <= 8'd0;
            lif_cnt         <= 8'd0;
            mac_done        <= 1'b0;
            score_valid     <= 1'b0;
            w_ren           <= 1'b0;
            w_raddr_flat    <= {(N_PE*16){1'b0}};
            x_ren           <= 1'b0;
            x_raddr         <= 16'd0;
            lif_wen         <= 1'b0;
            lif_capture     <= 1'b0;
            lif_acc         <= 16'd0;
            lif_idx         <= 7'd0;
            p0_en           <= 1'b0;
            p0_ph           <= 2'd0;
            p0_group        <= 8'd0;
            p0_col          <= 8'd0;
            p1_en           <= 1'b0;
            p1_ph           <= 2'd0;
            p1_group        <= 8'd0;
            p1_col          <= 8'd0;
            s_prev          <= {NH{1'b0}};
            ping_captured   <= 1'b0;
            mac_rd_addr     <= 11'd0;
            mac_rd_data_s1  <= 8'd0;
            for (ri = 0; ri < NH; ri = ri + 1) acc[ri]     <= 32'd0;
            for (ri = 0; ri < NO; ri = ri + 1) score[ri]   <= 32'd0;
            for (k  = 0; k  < N_PE; k  = k  + 1) begin
                p0_wdata[k]   <= 16'd0; p0_xop[k]   <= 16'd0;
                p1_wdata[k]   <= 16'd0; p1_xop[k]   <= 16'd0;
            end
        end else begin
            // Default deassertions
            mac_done      <= 1'b0;
            score_valid   <= 1'b0;
            w_ren         <= 1'b0;
            x_ren         <= 1'b0;
            lif_wen       <= 1'b0;
            lif_capture   <= 1'b0;

            // BRAM read latency alignment
            mac_rd_data_s1 <= mac_rd_data;

            // Pipeline shift
            p1_en      <= p0_en;
            p1_ph      <= p0_ph;
            p1_group   <= p0_group;
            p1_col     <= p0_col;
            for (k = 0; k < N_PE; k = k + 1) begin
                p1_wdata[k]   <= p0_wdata[k];
                p1_xop[k]     <= p0_xop[k];
            end

            // Accumulate result from pipeline stage 1
            if (p1_en) begin
                case (p1_ph)
                    PH_WIN, PH_WREC: begin
                        for (k = 0; k < N_PE; k = k + 1)
                            acc[p1_group * N_PE + k] <= acc[p1_group * N_PE + k] + mac_res[k];
                    end
                    PH_WOUT: score[p1_col] <= score[p1_col] + pe_total;
                    default: ;
                endcase
            end
            p0_en <= 1'b0;

            case (state)
                // ----------------------------------------------------------------
                // S_IDLE
                // ----------------------------------------------------------------
                S_IDLE: begin
                    if (mac_start) begin
                        ping_captured <= rd_ping_sel;
                        t_cnt    <= 6'd0;
                        for (ri = 0; ri < NO; ri = ri + 1) score[ri] <= 32'd0;
                        s_prev   <= {NH{1'b0}};
                        state    <= S_LOAD_X;
                    end
                end

                // ----------------------------------------------------------------
                // S_LOAD_X: clear acc[], prefetch first histogram addr + weights
                // FIX: Row index is just 'k' here because we are loading neurons 0..15
                // ----------------------------------------------------------------
                S_LOAD_X: begin
                    for (ri = 0; ri < NH; ri = ri + 1) acc[ri] <= 32'd0;

                    // Histogram address
                    mac_rd_addr <= {ping_captured, 4'd0, t_cnt};

                    // Prefetch W_IN: rows 0..N_PE-1, col=0
                    // row = k (0..15), col = 0, stride = NI
                    for (k = 0; k < N_PE; k = k + 1)
                        w_raddr_flat[k*16 +: 16] <= waddr(W_IN_BASE, k[7:0], 8'd0, NI);
                    w_ren       <= 1'b1;
                    x_raddr     <= t_cnt * NI;
                    x_ren       <= 1'b1;
                    group_cnt   <= 8'd0;
                    col_cnt     <= 8'd0;
                    state       <= S_W_IN;
                end

                // ----------------------------------------------------------------
                // S_W_IN: W_IN[group*N_PE .. (group+1)*N_PE-1][col] * x[col]
                //
                // FIX A: Row index must be 'group_cnt * N_PE + k' to address
                // unique neurons for each PE.
                // ----------------------------------------------------------------
                S_W_IN: begin
                    p0_en      <= 1'b1;
                    p0_ph      <= PH_WIN;
                    p0_group   <= group_cnt;
                    p0_col     <= col_cnt;
                    for (k = 0; k < N_PE; k = k + 1) begin
                        p0_wdata[k] <= w_rdata_flat[k*16 +: 16];
                        p0_xop[k]   <= {8'd0, mac_rd_data_s1};
                    end

                    if (group_cnt == GROUPS - 1) begin
                        // Last group for this col
                        if (col_cnt == NI - 1) begin
                            // Done with all inputs - move to W_REC
                            // FIX: Prefetch W_REC rows 0..N_PE-1, col=0
                            for (k = 0; k < N_PE; k = k + 1)
                                w_raddr_flat[k*16 +: 16] <= waddr(W_REC_BASE, k[7:0], 8'd0, NH);
                            w_ren       <= 1'b1;
                            group_cnt   <= 8'd0;
                            col_cnt     <= 8'd0;
                            state       <= S_W_REC;
                        end else begin
                            // Advance to next input channel
                            mac_rd_addr <= {ping_captured, col_cnt[3:0] + 4'd1, t_cnt};
                            
                            // FIX: Row index is 'k' because we reset group_cnt to 0 for next column
                            for (k = 0; k < N_PE; k = k + 1)
                                w_raddr_flat[k*16 +: 16] <= waddr(W_IN_BASE, k[7:0], col_cnt + 8'd1, NI);
                            w_ren       <= 1'b1;
                            group_cnt   <= 8'd0;
                            col_cnt     <= col_cnt + 8'd1;
                        end
                    end else begin
                        // Advance to next group (same channel)
                        // FIX: Row index = (group_cnt + 1) * N_PE + k
                        for (k = 0; k < N_PE; k = k + 1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_IN_BASE, (group_cnt + 8'd1) * N_PE + k[7:0], col_cnt, NI);
                        w_ren       <= 1'b1;
                        group_cnt   <= group_cnt + 8'd1;
                    end
                end

                // ----------------------------------------------------------------
                // S_W_REC: W_REC[group*N_PE .. (group+1)*N_PE-1][col] * s_prev[col]
                // FIX A: Row index = group_cnt * N_PE + k
                // ----------------------------------------------------------------
                S_W_REC: begin
                    p0_en      <= 1'b1;
                    p0_ph      <= PH_WREC;
                    p0_group   <= group_cnt;
                    p0_col     <= col_cnt;
                    for (k = 0; k < N_PE; k = k + 1) begin
                        p0_wdata[k] <= w_rdata_flat[k*16 +: 16];
                        p0_xop[k]   <= s_prev[col_cnt] ? 16'h0100 : 16'h0000;
                    end

                    if (group_cnt == GROUPS - 1) begin
                        if (col_cnt == NH - 1) begin
                            group_cnt   <= 8'd0;
                            col_cnt     <= 8'd0;
                            lif_cnt     <= 8'd0;
                            state       <= S_LIF_UPD;
                        end else begin
                            // Next column, reset group to 0
                            // Row index = k (since group is 0)
                            for (k = 0; k < N_PE; k = k + 1)
                                w_raddr_flat[k*16 +: 16] <= waddr(W_REC_BASE, k[7:0], col_cnt + 8'd1, NH);
                            w_ren       <= 1'b1;
                            group_cnt   <= 8'd0;
                            col_cnt     <= col_cnt + 8'd1;
                        end
                    end else begin
                        // Next group
                        // FIX: Row index = (group_cnt + 1) * N_PE + k
                        for (k = 0; k < N_PE; k = k + 1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_REC_BASE, (group_cnt + 8'd1) * N_PE + k[7:0], col_cnt, NH);
                        w_ren       <= 1'b1;
                        group_cnt   <= group_cnt + 8'd1;
                    end
                end

                // ----------------------------------------------------------------
                // S_LIF_UPD: Write acc[i][23:8] to LIF mem, then trigger spike capture.
                // ----------------------------------------------------------------
                S_LIF_UPD: begin
                    if (lif_cnt == 8'd0) begin
                        lif_cnt <= 8'd1;
                    end else if (lif_cnt <= NH) begin
                        lif_acc <= acc[lif_cnt - 1][23:8];
                        lif_idx <= lif_cnt[6:0] - 7'd1;
                        lif_wen <= 1'b1;
                        lif_cnt <= lif_cnt + 8'd1;
                    end else if (lif_cnt == NH + 1) begin
                        lif_capture <= 1'b1;
                        lif_cnt     <= lif_cnt + 8'd1;
                    end else if (lif_cnt == NH + 2) begin
                        lif_capture <= 1'b0;
                        lif_cnt     <= lif_cnt + 8'd1;
                    end else if (!capture_done) begin
                        lif_cnt <= lif_cnt; // wait
                    end else begin
                        s_prev      <= lif_spikes;
                        group_cnt   <= 8'd0;
                        col_cnt     <= 8'd0;
                        lif_cnt     <= 8'd0;
                        
                        // FIX B: Prefetch W_OUT with stride = NO (10)
                        // Row index = k (0..15)
                        for (k = 0; k < N_PE; k = k + 1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_OUT_BASE, k[7:0], 8'd0, NO);
                        w_ren <= 1'b1;
                        state <= S_W_OUT;
                    end
                end

                // ----------------------------------------------------------------
                // S_W_OUT: W_OUT[group*N_PE .. (group+1)*N_PE-1][col] * s_prev[row]
                // FIX A: Row index = group_cnt * N_PE + k
                // FIX B: Stride = NO
                // ----------------------------------------------------------------
                S_W_OUT: begin
                    p0_en      <= 1'b1;
                    p0_ph      <= PH_WOUT;
                    p0_group   <= group_cnt;
                    p0_col     <= col_cnt;
                    for (k = 0; k < N_PE; k = k + 1) begin
                        p0_wdata[k] <= w_rdata_flat[k*16 +: 16];
                        p0_xop[k]   <= s_prev[group_cnt * N_PE + k] ? 16'h0100 : 16'h0000;
                    end

                    if (group_cnt == GROUPS - 1) begin
                        if (col_cnt == NO - 1) begin
                            group_cnt <= 8'd0;
                            col_cnt   <= 8'd0;
                            state     <= S_NEXT_T;
                        end else begin
                            // Next class (col), reset group to 0
                            // Row index = k
                            // FIX B: Stride = NO
                            for (k = 0; k < N_PE; k = k + 1)
                                w_raddr_flat[k*16 +: 16] <= waddr(W_OUT_BASE, k[7:0], col_cnt + 8'd1, NO);
                            w_ren       <= 1'b1;
                            group_cnt   <= 8'd0;
                            col_cnt     <= col_cnt + 8'd1;
                        end
                    end else begin
                        // Next group
                        // FIX A: Row index = (group_cnt + 1) * N_PE + k
                        // FIX B: Stride = NO
                        for (k = 0; k < N_PE; k = k + 1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_OUT_BASE, (group_cnt + 8'd1) * N_PE + k[7:0], col_cnt, NO);
                        w_ren       <= 1'b1;
                        group_cnt   <= group_cnt + 8'd1;
                    end
                end

                // ----------------------------------------------------------------
                // S_NEXT_T: Loop back for next time step or finish
                // ----------------------------------------------------------------
                S_NEXT_T: begin
                    if (t_cnt >= T - 1) begin
                        state <= S_DONE;
                    end else begin
                        t_cnt <= t_cnt + 6'd1;
                        mac_rd_addr <= {ping_captured, 4'd0, t_cnt + 6'd1};
                        for (k = 0; k < N_PE; k = k + 1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_IN_BASE, k[7:0], 8'd0, NI);
                        w_ren       <= 1'b1;
                        group_cnt   <= 8'd0;
                        col_cnt     <= 8'd0;
                        for (ri = 0; ri < NH; ri = ri + 1) acc[ri] <= 32'd0;
                        state <= S_W_IN;
                    end
                end

                // ----------------------------------------------------------------
                // S_DONE: Signal completion for one cycle
                // ----------------------------------------------------------------
                S_DONE: begin
                    mac_done    <= 1'b1;
                    score_valid <= 1'b1;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule



`timescale 1ns / 1ps
module weight_router #(
    parameter N_PE = 16
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   ren,
    input  wire [N_PE*16-1:0]     raddr_flat,
    output wire [N_PE*16-1:0]     rdata_flat
);
    genvar p;
    generate
        for(p=0; p<N_PE; p=p+1) begin : pe_route
            wire [15:0] addr = raddr_flat[p*16 +: 16];
            wire [15:0] data_win, data_rec, data_out;
            
            wire sel_win = (addr < 16'h0800);
            wire sel_rec = (addr >= 16'h0800 && addr < 16'h4880);
            wire sel_out = (addr >= 16'h4880 && addr < 16'h4A00);
            
            wire [15:0] addr_win = addr;
            wire [15:0] addr_rec = addr - 16'h0880;
            wire [15:0] addr_out = addr - 16'h4880;
            
            weight_bank #(.MEM_FILE("win.mem"),  .MEM_DEPTH(2048))  u_win (
                .clk(clk), .rst(rst), .ren(ren), .raddr(addr_win), .rdata(data_win));
            weight_bank #(.MEM_FILE("wrec.mem"), .MEM_DEPTH(16384)) u_rec (
                .clk(clk), .rst(rst), .ren(ren), .raddr(addr_rec), .rdata(data_rec));
            weight_bank #(.MEM_FILE("wout.mem"), .MEM_DEPTH(384))  u_out (
                .clk(clk), .rst(rst), .ren(ren), .raddr(addr_out), .rdata(data_out));
            
            assign rdata_flat[p*16 +: 16] = sel_win ? data_win :
                                            sel_rec ? data_rec :
                                            sel_out ? data_out : 16'd0;
        end
    endgenerate
endmodule


`timescale 1ns / 1ps
module weight_bank #(
    parameter MEM_FILE = "weights.mem",
    parameter MEM_DEPTH = 2048
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        ren,
    input  wire [15:0] raddr,
    output reg  [15:0] rdata
);
    (* ram_style = "block" *) reg [15:0] mem [0:MEM_DEPTH-1];
    integer i;

    initial begin
        $readmemh(MEM_FILE, mem);
        for(i=0; i<MEM_DEPTH; i=i+1)
            if(mem[i] === 16'hxxxx) mem[i] = 16'h0000;
    end

    always @(posedge clk) begin
        if(rst) rdata <= 16'd0;
        else if(ren) begin
            if(raddr < MEM_DEPTH) rdata <= mem[raddr];
            else rdata <= 16'd0;
        end
    end
endmodule




   `timescale 1ns / 1ps
   `default_nettype none
   //////////////////////////////////////////////////////////////////////////////////
   // Module: lif_array
   //
   // LIF neuron array with register-based state (no BRAM dependency).
   // Reset logic explicitly initializes vm[] and accum[] to zero.
   //////////////////////////////////////////////////////////////////////////////////
   module lif_array #(
       parameter NH    = 128,
       parameter ALPHA = 16'h00E0,  // 0.875 in Q8.8
       parameter THETA = 16'h0100   // 1.0   in Q8.8
   )(
       input  wire clk,
       input  wire rst,
       input  wire clear_state,
       input  wire [15:0] lif_acc,
       input  wire [6:0]  lif_idx,
       input  wire lif_wen,
       input  wire lif_capture,
       output reg  [NH-1:0] lif_spikes,
       output reg  capture_done
   );
       // Neuron state registers
       reg [15:0] accum [0:NH-1];  // Synaptic current accumulator
       reg [15:0] vm    [0:NH-1];  // Membrane potential

       localparam [1:0] ST_IDLE = 2'd0, ST_SWEEP = 2'd1, ST_DONE = 2'd2;
       reg [1:0] cap_state;
       reg [7:0] cap_idx;

       // LIF update computation (combinational)
       wire signed [31:0] alpha_x_vm = $signed({1'b0, ALPHA}) * $signed({1'b0, vm[cap_idx]});
       wire [15:0] v_decayed = alpha_x_vm[23:8];  // Q8.8 result
       wire [16:0] v_new_full = {1'b0, v_decayed} + {1'b0, accum[cap_idx]};
       wire [15:0] v_new = v_new_full[16] ? 16'hFFFF : v_new_full[15:0];  // Saturate
       wire fire = (v_new >= THETA);

       reg [NH-1:0] spike_next;
       integer ci;

       always @(posedge clk) begin
           if (rst) begin
               // ⚠️ KEY FIX: Explicitly initialize ALL neuron state to zero
               cap_state    <= ST_IDLE;
               cap_idx      <= 8'd0;
               lif_spikes   <= {NH{1'b0}};
               capture_done <= 1'b0;
               spike_next   <= {NH{1'b0}};
               for (ci = 0; ci < NH; ci = ci + 1) begin
                   vm[ci]    <= 16'h0000;   // ← Membrane potential = 0
                   accum[ci] <= 16'h0000;   // ← Synaptic accumulator = 0
               end
           end else begin
               capture_done <= 1'b0;  // Default: deassert pulse

               // MAC writes accumulated current into LIF registers
               if (lif_wen) accum[lif_idx] <= lif_acc;

               // Global reset (optional runtime clear)
               if (clear_state) begin
                   for (ci = 0; ci < NH; ci = ci + 1) begin
                       vm[ci] <= 16'h0000;
                   end
               end

               case (cap_state)
                   ST_IDLE: begin
                       if (lif_capture) begin
                           cap_idx    <= 8'd0;
                           spike_next <= {NH{1'b0}};
                           cap_state  <= ST_SWEEP;
                       end
                   end

                   ST_SWEEP: begin
                       if (fire) begin
                           vm[cap_idx]       <= 16'h0000;        // Reset after fire
                           spike_next[cap_idx] <= 1'b1;          // Emit spike
                       end else begin
                           vm[cap_idx]       <= v_new;           // Update membrane
                           spike_next[cap_idx] <= 1'b0;
                       end
                       if (cap_idx == NH-1) begin
                           cap_state <= ST_DONE;
                       end else begin
                           cap_idx <= cap_idx + 8'd1;
                       end
                   end

                   ST_DONE: begin
                       lif_spikes   <= spike_next;               // Publish spikes
                       capture_done <= 1'b1;                     // Pulse to MAC
                       // ⚠️ KEY: Clear accumulators for next timestep
                       for (ci = 0; ci < NH; ci = ci + 1) begin
                           accum[ci] <= 16'h0000;
                       end
                       cap_state <= ST_IDLE;
                   end

                   default: cap_state <= ST_IDLE;
               endcase
           end
       end
   endmodule
   `default_nettype wire



`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.05.2026 10:27:42
// Design Name: 
// Module Name: overlap_voter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Module: overlap_voter
//
// HOW IT WORKS:
//   Window N arrives  → latched into score_N[], voter goes HOLD
//   Window N+1 arrives → score_N[k] + score_in[k] summed combinationally
//                        argmax of sums → pred_class, pred_valid pulses
//   Two windows needed before first prediction.
//   SLIDING_WINDOW=1: every window after the first produces a prediction.
//   SLIDING_WINDOW=0: paired mode (N,N+1), (N+2,N+3), etc.
//////////////////////////////////////////////////////////////////////////////////
module overlap_voter #(
    parameter  NUM_CLASSES    = 3,
    parameter  SCORE_WIDTH    = 32,               // Match mac_engine score[] width
    parameter  SUM_WIDTH      = SCORE_WIDTH + 1,  // 33-bit signed sum
    parameter  CLASS_BITS     = 4,                // ceil(log2(10)) = 4
    parameter  SLIDING_WINDOW = 0                 // 0=paired, 1=sliding
)(
    input  wire                               clk,
    input  wire                               rst,         // active-HIGH async


    input  wire [NUM_CLASSES*SCORE_WIDTH-1:0] score_in,
    input  wire                               score_valid, // 1-cycle pulse

    // To display/decision logic
    output reg  [CLASS_BITS-1:0]              pred_class,  // 0..9
    output reg  [SUM_WIDTH-1:0]               pred_score,  // combined score
    output reg                                pred_valid,  // 1-cycle pulse
    output reg                                voter_busy   // high between N and N+1
);

    // -------------------------------------------------------------------------
    // Unpack flat score bus → per-class wires
    // -------------------------------------------------------------------------
    wire signed [SCORE_WIDTH-1:0] score_in_w [0:NUM_CLASSES-1];
    genvar gi;
    generate
        for (gi = 0; gi < NUM_CLASSES; gi = gi + 1) begin : g_unpack
            assign score_in_w[gi] = score_in[gi*SCORE_WIDTH +: SCORE_WIDTH];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Score registers for Window N
    // -------------------------------------------------------------------------
    reg signed [SCORE_WIDTH-1:0] score_N [0:NUM_CLASSES-1];

    // -------------------------------------------------------------------------
    // Bypass mux: when second score_valid arrives, feed score_in directly
    // into the adder without waiting for score_Np1 to register
    // -------------------------------------------------------------------------
    reg state;
    localparam ST_IDLE = 1'b0, ST_HOLD = 1'b1;

    wire mux_bypass = (state == ST_HOLD) && score_valid;

    wire signed [SCORE_WIDTH-1:0] operand_b [0:NUM_CLASSES-1];
    generate
        for (gi = 0; gi < NUM_CLASSES; gi = gi + 1) begin : g_mux
            assign operand_b[gi] = mux_bypass ? score_in_w[gi] : {SCORE_WIDTH{1'b0}};
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Adder: score_N + operand_b (sign-extended to SUM_WIDTH)
    // -------------------------------------------------------------------------
    wire signed [SUM_WIDTH-1:0] score_sum [0:NUM_CLASSES-1];
    generate
        for (gi = 0; gi < NUM_CLASSES; gi = gi + 1) begin : g_add
            assign score_sum[gi] =
                {{1{score_N[gi][SCORE_WIDTH-1]}},   score_N[gi]}
              + {{1{operand_b[gi][SCORE_WIDTH-1]}}, operand_b[gi]};
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Argmax tree: find class with highest score_sum
    // Padded to TREE_LEAVES=16 (next power-of-2 >= 10)
    // Node encoding: {score[SUM_WIDTH-1:0], index[CLASS_BITS-1:0]}
    // -------------------------------------------------------------------------
    localparam TREE_LEAVES = 4;
    localparam TREE_NODES  = 2 * TREE_LEAVES;
    localparam NODE_W      = SUM_WIDTH + CLASS_BITS;

    wire [NODE_W-1:0] tree [1:TREE_NODES-1];

    generate
        for (gi = 0; gi < TREE_LEAVES; gi = gi + 1) begin : g_leaf
            if (gi < NUM_CLASSES) begin : real_leaf
                assign tree[TREE_LEAVES + gi] = {
                    score_sum[gi],
                    gi[CLASS_BITS-1:0]
                };
            end else begin : pad_leaf
                // Most-negative signed value - never wins
                assign tree[TREE_LEAVES + gi] = {
                    {1'b1, {(SUM_WIDTH-1){1'b0}}},
                    {CLASS_BITS{1'b1}}
                };
            end
        end
    endgenerate

    generate
        for (gi = 1; gi < TREE_LEAVES; gi = gi + 1) begin : g_cmp
            wire signed [SUM_WIDTH-1:0] lscore = tree[2*gi  ][NODE_W-1:CLASS_BITS];
            wire signed [SUM_WIDTH-1:0] rscore = tree[2*gi+1][NODE_W-1:CLASS_BITS];
            assign tree[gi] = (lscore >= rscore) ? tree[2*gi] : tree[2*gi+1];
        end
    endgenerate

    wire [CLASS_BITS-1:0] argmax_idx   = tree[1][CLASS_BITS-1:0];
    wire [SUM_WIDTH-1:0]  argmax_score = tree[1][NODE_W-1:CLASS_BITS];

    // -------------------------------------------------------------------------
    // FSM - active-HIGH async reset
    // -------------------------------------------------------------------------
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            voter_busy <= 1'b0;
            pred_valid <= 1'b0;
            pred_class <= {CLASS_BITS{1'b0}};
            pred_score <= {SUM_WIDTH{1'b0}};
            for (k = 0; k < NUM_CLASSES; k = k + 1)
                score_N[k] <= {SCORE_WIDTH{1'b0}};
        end else begin
            pred_valid <= 1'b0;  // default: deassert

            case (state)

                ST_IDLE: begin
                    voter_busy <= 1'b0;
                    if (score_valid) begin
                        for (k = 0; k < NUM_CLASSES; k = k + 1)
                            score_N[k] <= score_in_w[k];
                        state      <= ST_HOLD;
                        voter_busy <= 1'b1;
                    end
                end

                ST_HOLD: begin
                    voter_busy <= 1'b1;
                    if (score_valid) begin
                        // argmax fires this cycle (mux_bypass routes score_in_w
                        // directly into the combinational adder)
                        pred_class <= argmax_idx;
                        pred_score <= argmax_score;
                        pred_valid <= 1'b1;

                        if (SLIDING_WINDOW) begin
                            // Promote N+1 → N, stay in HOLD for every new window
                            for (k = 0; k < NUM_CLASSES; k = k + 1)
                                score_N[k] <= score_in_w[k];
                        end else begin
                            // Paired mode: (N,N+1), (N+2,N+3), ...
                            state      <= ST_IDLE;
                            voter_busy <= 1'b0;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire



`timescale 1ns / 1ps
`default_nettype none
module led_out (
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] pred_class,   // 0=Yes, 1=No, 2=Gibberish
    input  wire       pred_valid,   // 1-cycle pulse from overlap_voter
    output reg  [1:0] led
);
always @(posedge clk) begin
    if (rst) begin
        led <= 2'b00;
    end else if (pred_valid) begin
        case (pred_class)
            2'd0: led <= 2'b01; // "yes" -> 1
            2'd1: led <= 2'b10; // "no" 
            2'd2: led <= 2'b00; // "gibberish" 
            default: led <= 2'b11;
        endcase
    end
end
endmodule
`default_nettype wire
