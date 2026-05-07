`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.05.2026 10:39:34
// Design Name: 
// Module Name: top_layer
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


module top_layer #(
    parameter SAMPLE_EN_PERIOD = 6250,   // 16 kHz @ 125 MHz reference
    parameter NUM_LOOPS        = 2,      // Window replay count for overlap voter
    parameter FIFO_DEPTH       = 64      // AER FIFO depth (power of 2)
)(
    // === Top-level Ports ===
    input  wire        clk_125_p,          // Differential 125 MHz clock (+)
    input  wire        clk_125_n,          // Differential 125 MHz clock (-)
    input  wire        rst                // Active-high reset
            // UART output: class ID + confidence
);
    
    
        // === Optional Status Outputs ===
    wire        audio_done;         // Frontend: ROM playback complete
    wire        out_result_valid;   // Backend: Final classification ready
    wire  window_ready_out;   
    wire        uart_tx;    // Backend: Window accumulation complete
    //==========================================================================
    // Internal Signals
    //==========================================================================
    //--- Clocks ---
    wire clk_buf, clk1, clk_50;  // clk=125MHz (frontend), clk_50=50MHz (backend)
    wire [6:0]percent_val;
    wire [3:0]cmd_id;
    wire clk;
         IBUFDS ibufds_inst (
       .I(clk_125_p),
       .IB(clk_125_n),
       .O(clk_buf)
     );

// Global clock
     BUFG bufg_inst (
      .I(clk_buf),
      .O(clk1)
   );
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
    //--- Frontend audio processing ---
    wire [15:0] fft1;
    wire [15:0] fft2;
    wire [15:0] fft3;
    wire [15:0] fft4;
    wire [15:0] fft5;
    wire [15:0] fft6;
    wire [15:0] fft7;
    wire [15:0] fft8;
    wire [15:0] fft9;
    wire [15:0] fft10;
    wire [15:0] fft11;
    wire [15:0] fft12;
    wire [15:0] fft13;
    wire [15:0] fft14;
    wire [15:0] fft15;
    wire [15:0] fft16;
    wire biquad_valid;

    wire audio_valid;
    wire [15:0] emph_out;
    wire pm_out_valid;
    wire [255:0] envelope_packed;
    wire [15:0] env_ch [0:15];
    wire [15:0] spike_bus;

    
    //--- AER Encoder (real-time, from lif_top) ---
    wire [23:0] aer_data;       // {channel[3:0], timestamp[19:0]}
    wire        aer_enc_valid;
    wire        aer_ready;          // Backpressure from FIFO
    
    //--- AER FIFO ---
    wire [23:0] fifo_dout;
    wire        fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;
    reg        fifo_rd_valid;      // Delayed rd_en for decoder timing
    
    //--- AER Decoder + Timestamp Manager (125 MHz domain) ---
    wire [3:0]  aer_ch_decoded;
    wire [19:0] aer_ts_decoded;
    wire        ts_decoded_valid, spike_detected;
    wire [31:0] ts_abs, window_start;
    wire        ts_abs_valid;
    wire [19:0] window_offset_125;  // Window offset @125MHz
    
    //--- CDC: 125MHz → 50MHz for backend ---
    wire [3:0]  channel_Id_50;
    wire [19:0] window_offset_50;
    wire        timestamp_valid_50;
    
    //--- Backend processing signals (50 MHz) ---
    wire        window_ready_slow, rd_ping_sel, mac_done;
    wire [10:0] mac_rd_addr;
    wire [7:0]  mac_rd_data;
    wire        score_valid_mac, score_valid_final;
    wire [319:0] score_out_mac;
    
    wire [32:0]  pred_score;
    
    //--- Validity signals ---
    wire rom_valid, emph_valid, ihc_valid;
    wire speech_valid = 1'b1;  // Always valid (VAD removed per CORA v4)
    
    //--- CDC: 50MHz → 125MHz (window_open pulse for timestamp_manager) ---
    wire window_open_125;  // Rising-edge pulse from backend window_ready
    
    
        //==================================================================
    // Clock Divider: Generate 16kHz enable from 100MHz clock
    //==================================================================
    reg [12:0] clk_div_counter;
    reg sample_en;
    
    always @(posedge clk) begin
        if (!rst) begin
            clk_div_counter <= 13'd0;
            sample_en   <= 1'b0;
        end else begin
            sample_en <= 1'b0;
            if (clk_div_counter == 13'd6249) begin  // 100MHz/16kHz - 1
                clk_div_counter <= 13'd0;
                sample_en   <= 1'b1;
            end else begin
                clk_div_counter <= clk_div_counter + 13'd1;
            end
        end
    end

    //==========================================================================
    // 2. AUDIO ROM (Source)
    //==========================================================================
    wire [15:0] rom_pcm_raw;
    wire        rom_done;
    wire [15:0] x_out;


    audio_rom #(.N_SAMPLES(20160)) u_audio_rom (
        .clk       (clk),
        .rst       (rst),
        .sample_en (sample_en),
        .x_out     (x_out),
        .done      (rom_done),
        .valid     (audio_valid)
    );
    assign audio_done = rom_done;
    
    //==========================================================================
    // 3. PRE-EMPHASIS FILTER
    //==========================================================================
    pm_filter u_emph (
        .clk      (clk),
        .rst      (rst),
        .valid_in (audio_valid),
        .x_n      (x_out),
        .y_n      (emph_out),
        .valid_out(pm_out_valid)
    );
    
    //==========================================================================
    // 4. IHC SYSTEM: FFT Filterbank + 16× IHC Channels
    //==========================================================================
    ihc_top u_ihc_system (
        .clk          (clk),
        .rst          (rst),
        .sample_en    (pm_out_valid),
        .audio_in     (emph_out),
        .envelope_out (envelope_packed),
        .valid_out    (ihc_valid),
        .y1 (fft1),
        .y2 (fft2),
        .y3 (fft3),
        .y4 (fft4),
        .y5 (fft5),
        .y6 (fft6),
        .y7 (fft7),
        .y8 (fft8),
        .y9 (fft9),
        .y10 (fft10),
        .y11 (fft11),
        .y12 (fft12),
        .y13 (fft13),
        .y14 (fft14),
        .y15(fft15),
        .y16 (fft16),
        .biquad_valid(biquad_valid)
    );
    
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : slice_env
            assign env_ch[i] = envelope_packed[(i+1)*16-1 : i*16];
        end
    endgenerate
    
    //==========================================================================
    // 5. LIF SYSTEM: 16 Neurons → spike_bus (NO embedded AER encoder here)
    //==========================================================================
    lif_top  u_lif_system (
        .clk        (clk),
        .rst        (rst),
        .sample_en  (ihc_valid),
        .ihc_ch1    (env_ch[0]), .ihc_ch2(env_ch[1]), .ihc_ch3(env_ch[2]), .ihc_ch4(env_ch[3]),
        .ihc_ch5    (env_ch[4]), .ihc_ch6(env_ch[5]), .ihc_ch7(env_ch[6]), .ihc_ch8(env_ch[7]),
        .ihc_ch9    (env_ch[8]), .ihc_ch10(env_ch[9]), .ihc_ch11(env_ch[10]), .ihc_ch12(env_ch[11]),
        .ihc_ch13   (env_ch[12]), .ihc_ch14(env_ch[13]), .ihc_ch15(env_ch[14]), .ihc_ch16(env_ch[15]),
        .spike_bus  (spike_bus)  // ← 16-bit spike vector OUTPUT
    );
    
    //==========================================================================
    // 6. REAL AER ENCODER: spike_bus → {ch, ts} packets (125 MHz)
    //==========================================================================
    aer_encoder u_aer_encoder (
        .clk        (clk),
        .rst        (rst),
        .sample_en  (sample_en),      // Timestamp increments at 16 kHz
        .spike      (spike_bus),      // 16-bit spike vector from lif_top
        .data       (aer_data),   // 24-bit AER packet {ch[3:0], ts[19:0]}
        .aer_valid  (aer_enc_valid),  // Valid pulse
        .aer_ready  (aer_ready)       // Backpressure from FIFO
    );
    
    //==========================================================================
    // 7. AER FIFO: Buffer between encoder (125MHz) and decoder (125MHz)
    // Prevents loss if decoder is busy; depth=64 handles burst spikes
    //==========================================================================
    assign fifo_wr_en = aer_enc_valid && aer_ready;
    assign aer_ready  = !fifo_full;
    assign fifo_rd_en = !fifo_empty;
    
    // Delay rd_en by 1 cycle for decoder timing (matches original aer_pipeline)
    always @(posedge clk) begin
        if (!rst) fifo_rd_valid <= 1'b0;
        else     fifo_rd_valid <= fifo_rd_en;
    end
    
    fifo  u_aer_fifo (
        .clk    (clk),
        .rst    (rst),
        .wr_en  (fifo_wr_en),
        .rd_en  (fifo_rd_en),
        .din    (aer_enc_data),
        .dout   (fifo_dout),
        .full   (fifo_full),
        .empty  (fifo_empty)
    );
    
    //==========================================================================
    // 8. AER DECODER: Extract channel + timestamp from 24-bit packet
    //==========================================================================
    input_from_aer u_aer_decoder (
        .clk            (clk),
        .rst            (rst),
        .in             (fifo_dout),
        .aer_valid      (fifo_rd_valid),
        .spike_detected (spike_detected),  // Unused but kept for compatibility
        .channel_Id     (aer_ch_decoded),
        .timestamp      (aer_ts_decoded),
        .timestamp_valid(ts_decoded_valid)
    );
    
    //==========================================================================
    // 9. TIMESTAMP MANAGER: Handle 20-bit rollover → 32-bit absolute time
    // Also computes window_offset relative to window_start
    //==========================================================================
    timestamp_manager u_ts_mgr (
        .clk          (clk),
        .rst          (rst),
        .timestamp    (aer_ts_decoded),
        .ts_valid     (ts_decoded_valid),
        .window_open  (window_open_125),  // ← CDC from backend (50MHz→125MHz)
        .ts_abs       (ts_abs),
        .ts_abs_valid (ts_abs_valid),
        .window_start (window_start),
        .window_offset(window_offset_125)
    );
    
    //==========================================================================
    // 10. CDC: 125 MHz → 50 MHz (AER events to backend)
    // 2-flop synchronizer for valid + bus sampling
    //==========================================================================
    cdc_sync_2flop u_cdc_aer (
        .clk_fast(clk), 
        .clk_slow(clk_50), 
        .rst(rst),
        .d_in(ts_abs_valid), 
        .ch_in(aer_ch_decoded), 
        .ts_in(window_offset_125),
        .d_out(timestamp_valid_50), 
        .ch_out(channel_Id_50), 
        .ts_out(window_offset_50)
    );
    
    //==========================================================================
    // 11. CDC: 50 MHz → 125 MHz (window_open pulse to timestamp_manager)
    // 3-flop sync + edge detect for 1-cycle pulse in fast domain
    //==========================================================================
    reg win_rdy_sync1, win_rdy_sync2, win_rdy_sync3;
    always @(posedge clk) begin
        if (!rst) begin
            win_rdy_sync1 <= 1'b0;
            win_rdy_sync2 <= 1'b0;
            win_rdy_sync3 <= 1'b0;
        end else begin
            win_rdy_sync1 <= window_ready_slow;  // From backend @50MHz
            win_rdy_sync2 <= win_rdy_sync1;
            win_rdy_sync3 <= win_rdy_sync2;
        end
    end
    assign window_open_125 = win_rdy_sync2 & ~win_rdy_sync3;  // Rising edge detect
    
    //==========================================================================
    // 12. WINDOW ACCUMULATOR (S10) - 50 MHz Domain
    //==========================================================================
    s10_window_accumulator u_win_acc (
        .clk          (clk_50),
        .rst          (rst),
        .window_offset(window_offset_50),    // From CDC
        .ts_abs_valid (timestamp_valid_50),  // From CDC
        .spike_ch     (channel_Id_50),       // From CDC
        .speech_valid (speech_valid),
        .window_open  (),                    // Unused in streaming mode
        .window_ready (window_ready_slow),   // Pulse when window complete
        .rd_ping_sel  (rd_ping_sel),
        .mac_rd_addr  (mac_rd_addr),
        .mac_done     (mac_done),
        .mac_rd_data  (mac_rd_data)
    );
    assign window_ready_out = window_ready_slow;
    
    //==========================================================================
    // 13. MAC START PULSE (1-cycle delay for timing)
    //==========================================================================
    reg mac_start_r;
    always @(posedge clk_50) begin
        if (!rst) mac_start_r <= 1'b0;
        else     mac_start_r <= window_ready_slow;
    end
    wire mac_start = mac_start_r;
    
    //==========================================================================
    // 14. MAC ENGINE + WEIGHT ROUTER + LIF ARRAY (50 MHz)
    //==========================================================================
    wire [255:0] mac_w_raddr, mac_w_rdata;
    wire         mac_w_ren;
    wire [15:0]  mac_lif_acc;
    wire [6:0]   mac_lif_idx;
    wire         mac_lif_wen, mac_lif_capture, lif_capture_done;
    wire [127:0] mac_lif_spikes;
    wire [3:0]   pred_class;
    mac_engine  u_mac (
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
        .ren(mac_w_ren), 
        .raddr_flat(mac_w_raddr), 
        .rdata_flat(mac_w_rdata)
    );
    
    lif_array #(.NH(128), .ALPHA(16'h00E0), .THETA(16'h0100)) u_lif (
        .clk(clk_50), .rst(rst), .clear_state(1'b0),
        .lif_acc(mac_lif_acc), 
        .lif_idx(mac_lif_idx), 
        .lif_wen(mac_lif_wen),
        .lif_capture(mac_lif_capture),
        .lif_spikes(mac_lif_spikes),
        .capture_done(lif_capture_done)
    );
    
    //==========================================================================
    // 15. OVERLAP VOTER + UART OUTPUT (50 MHz)
    //==========================================================================
    overlap_voter #(
        .NUM_CLASSES(10), .SCORE_WIDTH(32), .SUM_WIDTH(33),
        .CLASS_BITS(4), .SLIDING_WINDOW(0)
    ) u_overlap_voter (
        .clk(clk_50), .rst(rst),
        .score_in(score_out_mac),
        .score_valid(score_valid_mac),
        .pred_class(pred_class),
        .pred_score(pred_score),
        .pred_valid(score_valid_final),
        .voter_busy()
    );
    
    uart_result_hex_tx #(
        .CLK_FREQ(50_000_000), .BAUD_RATE(115200)
    ) u_uart (
        .clk(clk_50), .rst(rst),
        .tx_trigger(score_valid_final),
        .cmd_id(pred_class),
        .score_in(pred_score[32:1]),
        .uart_tx(uart_tx),
        .tx_busy()
    );
    
    //==========================================================================
    // 16. COMPLETION LOGIC
    //==========================================================================
    reg test_done;
    always @(posedge clk_50) begin
        if (!rst) test_done <= 1'b0;
        else if (score_valid_final) test_done <= 1'b1;
    end
    assign out_result_valid = score_valid_final;
    


ila_0 your_instance_name (
	.clk(clk), // input wire clk


	.probe0(rst), // input wire [0:0]  probe0  
	.probe1(sample_en), // input wire [0:0]  probe1 
	.probe2(emph_out), // input wire [15:0]  probe2 
	.probe3(biquad_valid), // input wire [0:0]  probe3 
	.probe4(fft1), // input wire [15:0]  probe4 
	.probe5(fft2), // input wire [15:0]  probe5 
	.probe6(fft3), // input wire [15:0]  probe6 
	.probe7(fft4), // input wire [15:0]  probe7 
	.probe8(fft5), // input wire [15:0]  probe8 
	.probe9(fft6), // input wire [15:0]  probe9 
	.probe10(fft7), // input wire [15:0]  probe10 
	.probe11(fft8), // input wire [15:0]  probe11 
	.probe12(fft9), // input wire [15:0]  probe12 
	.probe13(fft10), // input wire [15:0]  probe13 
	.probe14(fft11), // input wire [15:0]  probe14 
	.probe15(fft12), // input wire [15:0]  probe15 
	.probe16(fft13), // input wire [15:0]  probe16 
	.probe17(fft14), // input wire [15:0]  probe17 
	.probe18(fft15), // input wire [15:0]  probe18 
	.probe19(fft16) // input wire [15:0]  probe19
);
endmodule
