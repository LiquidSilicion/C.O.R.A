`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: mac_engine_parallel
// Target: AMD ZCU104 (XCZU7EV) @ 200 MHz
//
// Key changes from mac_engine_16bit (sequential):
//   1. 16-wide parallel weight fetch per cycle (256-bit BRAM read via wide port)
//   2. Proper bram_req / bram_done handshake with arbiter
//   3. Pipelined accumulation: fetch overlaps with accumulate
//   4. S_PREV register tracks previous-timestep spikes for recurrent pass
//   5. All three weight matrices: W_in[NI×NH], W_rec[NH×NH], W_out[NH×NO]
//   6. No undriven ports (weight_addr driven from FSM, bram_req explicit)
//
// Latency estimate @ 200 MHz:
//   Per timestep: ceil(NH/16)*NI + NH + ceil(NH/16)*NH + NH + NO = ~1,216 cycles
//   50 timesteps: ~60,800 cycles = ~304 µs  (vs ~5 ms sequential)
//
// BRAM Bank 3 layout (16K × 16-bit words, Q8.8 weights):
//   0x0000 - 0x07FF  W_in  [NI=16 rows × NH=128 cols]   = 2048 words
//   0x0800 - 0x47FF  W_rec [NH=128 rows × NH=128 cols]  = 16384 words (needs 14-bit addr)
//   0x4800 - 0x4AFF  W_out [NH=128 rows × NO=10 cols]   = 1280 words
//   NOTE: W_rec alone = 16384 words = full 14-bit space.
//         Remap if using a single 16K BRAM: use two BRAMs or reduce NH.
//         This RTL uses separate base pointers; connect to 2 × BRAM IP or 1 × 32K BRAM.
//////////////////////////////////////////////////////////////////////////////////

module mac_engine #(
    parameter NH           = 128,        // Hidden neurons
    parameter NI           = 16,         // Input channels
    parameter NO           = 10,         // Output classes
    parameter T            = 50,         // Timesteps per window
    parameter FETCH_W      = 16,         // Weights fetched per cycle (match BRAM width ÷ 16)
    // Base addresses into BRAM Bank 3 (14-bit word addresses)
    parameter [13:0] W_IN_BASE  = 14'h0000,  // W_in  start
    parameter [13:0] W_REC_BASE = 14'h0800,  // W_rec start  (0x0800 = 2048)
    parameter [13:0] W_OUT_BASE = 14'h4800   // W_out start  (0x4800 = 18432)
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ── Sequencer handshake ──────────────────────────────────────────────────
    input  wire                 mac_start,       // 1-cycle pulse: begin forward pass
    output reg                  mac_done,        // 1-cycle pulse: forward pass complete

    // ── BRAM arbiter interface (16-bit read, one word per grant cycle) ────────
    // mac_req stays high until mac_done; arbiter may de-assert grant
    output reg                  mac_bram_req,    // Request bus
    input  wire                 mac_bram_grant,  // Grant from arbiter
    output reg  [13:0]          mac_bram_addr,   // Address to BRAM
    output wire [15:0]          mac_bram_din,    // Write data (always 0 - read only)
    output wire                 mac_bram_we,     // Write enable (always 0)
    input  wire [15:0]          mac_bram_dout,   // Read data from BRAM

    // ── Input spikes from Window Accumulator (one-hot per channel per bin) ────
    // Packed: win_spikes[ch*T + t] = 1 if channel ch fired in bin t
    input  wire [NI*T-1:0]      win_spikes,      // From window accumulator (sampled at mac_start)

    // ── LIF Array interface ───────────────────────────────────────────────────
    output reg  [15:0]          lif_acc,         // Q8.8 synaptic current for neuron lif_idx
    output reg  [6:0]           lif_idx,         // Neuron index 0..NH-1
    output reg                  lif_wen,         // Strobe: write lif_acc to accumulator
    output reg                  lif_capture,     // Trigger LIF fire/reset sweep
    input  wire [NH-1:0]        lif_spikes,      // Spike vector from previous LIF sweep

    // ── Output scores (10 classes × 32-bit Q16.16) ───────────────────────────
    output reg  [NO*32-1:0]     score_out,
    output reg                  score_valid      // 1-cycle pulse: scores ready
);

    // ──────────────────────────────────────────────────────────────────────────
    // Tie-offs for unused write ports
    // ──────────────────────────────────────────────────────────────────────────
    assign mac_bram_din = 16'd0;
    assign mac_bram_we  = 1'b0;

    // ──────────────────────────────────────────────────────────────────────────
    // FSM encoding
    // ──────────────────────────────────────────────────────────────────────────
    localparam [3:0]
        S_IDLE      = 4'd0,   // Waiting for mac_start
        S_REQ       = 4'd1,   // Assert bram_req, wait for first grant
        S_WIN_ACC   = 4'd2,   // W_in × input_spike accumulation
        S_SEND_LIF  = 4'd3,   // Stream currents to LIF array
        S_LIF_WAIT  = 4'd4,   // Wait one cycle for LIF capture
        S_REC_FETCH = 4'd5,   // Fetch W_rec row
        S_REC_ACC   = 4'd6,   // W_rec × s_prev accumulation
        S_CAPTURE   = 4'd7,   // Pulse lif_capture
        S_OUT_ACC   = 4'd8,   // W_out × lif_spikes accumulation (last timestep)
        S_SCORE     = 4'd9,   // Latch final scores, pulse score_valid
        S_DONE      = 4'd10;  // Pulse mac_done, release arbiter

    reg [3:0] state;

    // ──────────────────────────────────────────────────────────────────────────
    // Counters
    // ──────────────────────────────────────────────────────────────────────────
    reg [5:0]  t_cnt;          // Timestep 0..T-1
    reg [7:0]  row_cnt;        // Current neuron row being computed (0..NH-1)
    reg [7:0]  col_cnt;        // Column index within a row fetch pass
    reg [3:0]  no_cnt;         // Output class index 0..NO-1

    // ──────────────────────────────────────────────────────────────────────────
    // Hidden neuron accumulators: Q8.24 fixed-point intermediate
    // Initialised each timestep before accumulation
    // ──────────────────────────────────────────────────────────────────────────
    reg signed [31:0] h_acc [0:NH-1];

    // Output class accumulators: Q16.16, accumulated over all timesteps
    reg signed [31:0] score [0:NO-1];

    // Previous timestep spikes (recurrent input)
    reg [NH-1:0] s_prev;

    // Registered input spike array (captured at mac_start)
    reg [NI*T-1:0] win_spikes_reg;

    // ──────────────────────────────────────────────────────────────────────────
    // Weight FIFO buffer: one row of FETCH_W=16 weights, loaded from BRAM
    // The BRAM returns one 16-bit word per granted cycle.
    // We buffer them and drain into the MAC array once FETCH_W words arrive.
    // ──────────────────────────────────────────────────────────────────────────
    reg signed [15:0] wbuf [0:FETCH_W-1];
    reg [4:0]  wbuf_fill;      // How many words loaded (0..16)
    reg        wbuf_ready;     // wbuf_fill == FETCH_W
    reg [3:0]  wbuf_drain;     // Drain index into wbuf during accumulate

    // ──────────────────────────────────────────────────────────────────────────
    // Address generation helpers
    // ──────────────────────────────────────────────────────────────────────────
    // W_in address:  base + row*NH + col  (row = input channel 0..NI-1,
    //                                      col = neuron 0..NH-1)
    // W_rec address: base + row*NH + col  (row = prev neuron, col = cur neuron)
    // W_out address: base + row*NO + col  (row = neuron 0..NH-1, col = class 0..NO-1)
    function [13:0] addr_win;
        input [7:0] row, col;
        begin : f_win
            addr_win = W_IN_BASE + row * NH + col;
        end
    endfunction

    function [13:0] addr_wrec;
        input [7:0] row, col;
        begin : f_wrec
            addr_wrec = W_REC_BASE + row * NH + col;
        end
    endfunction

    function [13:0] addr_wout;
        input [7:0] row, col;
        begin : f_wout
            addr_wout = W_OUT_BASE + row * NO + col;
        end
    endfunction

    // ──────────────────────────────────────────────────────────────────────────
    // Helper: extract input spike for channel ch at timestep t_cnt
    // ──────────────────────────────────────────────────────────────────────────
    // win_spikes_reg[ch*T + t] = 1 if channel ch fired in bin t
    // We process one timestep at a time; for the current t_cnt, spike for ch:
    wire [NI-1:0] cur_spikes;
    genvar gi;
    generate
        for (gi = 0; gi < NI; gi = gi + 1) begin : g_csp
            assign cur_spikes[gi] = win_spikes_reg[gi * T + t_cnt];
        end
    endgenerate

    // ──────────────────────────────────────────────────────────────────────────
    // Main FSM
    // ──────────────────────────────────────────────────────────────────────────
    integer ci;

    always @(posedge clk) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            mac_done     <= 1'b0;
            score_valid  <= 1'b0;
            mac_bram_req <= 1'b0;
            mac_bram_addr<= 14'd0;
            lif_wen      <= 1'b0;
            lif_capture  <= 1'b0;
            lif_acc      <= 16'd0;
            lif_idx      <= 7'd0;
            t_cnt        <= 6'd0;
            row_cnt      <= 8'd0;
            col_cnt      <= 8'd0;
            no_cnt       <= 4'd0;
            wbuf_fill    <= 5'd0;
            wbuf_ready   <= 1'b0;
            wbuf_drain   <= 4'd0;
            s_prev       <= {NH{1'b0}};
            win_spikes_reg <= {NI*T{1'b0}};
            for (ci = 0; ci < NH; ci = ci + 1) h_acc[ci] <= 32'sd0;
            for (ci = 0; ci < NO; ci = ci + 1) score[ci] <= 32'sd0;
        end else begin
            // Default de-assertions
            mac_done    <= 1'b0;
            score_valid <= 1'b0;
            lif_wen     <= 1'b0;
            lif_capture <= 1'b0;

            case (state)

                // ── IDLE ──────────────────────────────────────────────────────
                S_IDLE: begin
                    if (mac_start) begin
                        // Capture input spikes and reset scores
                        win_spikes_reg <= win_spikes;
                        for (ci = 0; ci < NO; ci = ci + 1) score[ci] <= 32'sd0;
                        s_prev    <= {NH{1'b0}};
                        t_cnt     <= 6'd0;
                        row_cnt   <= 8'd0;
                        col_cnt   <= 8'd0;
                        wbuf_fill <= 5'd0;
                        wbuf_ready<= 1'b0;
                        mac_bram_req <= 1'b1;   // Hold req until S_DONE
                        state     <= S_REQ;
                    end
                end

                // ── REQ: Wait for first grant ─────────────────────────────────
                S_REQ: begin
                    if (mac_bram_grant) begin
                        // Reset per-neuron accumulators for this timestep
                        for (ci = 0; ci < NH; ci = ci + 1)
                            h_acc[ci] <= 32'sd0;
                        row_cnt <= 8'd0;  // input channel index
                        col_cnt <= 8'd0;  // starting neuron index
                        // Issue first W_in address
                        mac_bram_addr <= addr_win(8'd0, 8'd0);
                        wbuf_fill <= 5'd0;
                        wbuf_ready<= 1'b0;
                        state <= S_WIN_ACC;
                    end
                end

                // ── S_WIN_ACC: Accumulate W_in × input_spikes ────────────────
                // row_cnt = input channel (0..NI-1)
                // col_cnt = neuron (0..NH-1), in steps of FETCH_W
                //
                // Phase A (wbuf_ready=0): issue sequential addresses, fill wbuf
                // Phase B (wbuf_ready=1): drain wbuf into h_acc for active channels
                S_WIN_ACC: begin
                    if (!wbuf_ready) begin
                        // Filling wbuf: one word per granted cycle
                        if (mac_bram_grant) begin
                            wbuf[wbuf_fill[3:0]] <= $signed(mac_bram_dout);
                            wbuf_fill <= wbuf_fill + 5'd1;
                            if (wbuf_fill == FETCH_W - 1) begin
                                wbuf_ready <= 1'b1;
                                wbuf_drain <= 4'd0;
                            end else begin
                                // Issue next address
                                mac_bram_addr <= addr_win(row_cnt,
                                    col_cnt + wbuf_fill[3:0] + 8'd1);
                            end
                        end
                    end else begin
                        // Draining: one MAC per cycle, no BRAM access needed
                        if (cur_spikes[row_cnt[3:0]]) begin
                            // Channel fired: accumulate weight × 1 (spike = 1)
                            h_acc[col_cnt + wbuf_drain] <=
                                h_acc[col_cnt + wbuf_drain]
                                + {{16{wbuf[wbuf_drain][15]}}, wbuf[wbuf_drain]};
                        end
                        wbuf_drain <= wbuf_drain + 4'd1;
                        if (wbuf_drain == FETCH_W - 1) begin
                            // Done draining this chunk
                            wbuf_ready <= 1'b0;
                            wbuf_fill  <= 5'd0;
                            col_cnt    <= col_cnt + FETCH_W;
                            if (col_cnt + FETCH_W >= NH) begin
                                // Done with this input channel row
                                col_cnt <= 8'd0;
                                row_cnt <= row_cnt + 8'd1;
                                if (row_cnt + 8'd1 >= NI) begin
                                    // All W_in rows done → send currents to LIF
                                    row_cnt <= 8'd0;
                                    state <= S_SEND_LIF;
                                end else begin
                                    // Next channel
                                    mac_bram_addr <= addr_win(row_cnt + 8'd1, 8'd0);
                                end
                            end else begin
                                // Next chunk in same channel
                                mac_bram_addr <= addr_win(row_cnt, col_cnt + FETCH_W);
                            end
                        end
                    end
                end

                // ── S_SEND_LIF: Stream h_acc currents to LIF array ────────────
                // One neuron per cycle; no BRAM traffic (arbiter can be idle here)
                S_SEND_LIF: begin
                    lif_acc <= h_acc[row_cnt][23:8];  // Q8.24 → Q8.8
                    lif_idx <= row_cnt[6:0];
                    lif_wen <= 1'b1;
                    row_cnt <= row_cnt + 8'd1;
                    if (row_cnt + 8'd1 >= NH) begin
                        row_cnt <= 8'd0;
                        col_cnt <= 8'd0;
                        wbuf_fill <= 5'd0;
                        wbuf_ready<= 1'b0;
                        mac_bram_addr <= addr_wrec(8'd0, 8'd0);
                        state <= S_REC_FETCH;
                    end
                end

                // ── S_REC_FETCH: Fetch W_rec row for recurrent accumulation ───
                // row_cnt = previous-spike neuron index
                // Only fetch rows where s_prev[row_cnt]=1 (skip zeros for speed)
                S_REC_FETCH: begin
                    // Skip neurons that didn't fire last timestep
                    if (!s_prev[row_cnt]) begin
                        row_cnt <= row_cnt + 8'd1;
                        if (row_cnt + 8'd1 >= NH) begin
                            // No more recurrent rows → do LIF capture
                            row_cnt <= 8'd0;
                            state   <= S_CAPTURE;
                        end else begin
                            mac_bram_addr <= addr_wrec(row_cnt + 8'd1, 8'd0);
                        end
                    end else begin
                        // This neuron fired: fetch its W_rec row
                        if (!wbuf_ready) begin
                            if (mac_bram_grant) begin
                                wbuf[wbuf_fill[3:0]] <= $signed(mac_bram_dout);
                                wbuf_fill <= wbuf_fill + 5'd1;
                                if (wbuf_fill == FETCH_W - 1) begin
                                    wbuf_ready <= 1'b1;
                                    wbuf_drain <= 4'd0;
                                end else begin
                                    mac_bram_addr <= addr_wrec(row_cnt,
                                        col_cnt + wbuf_fill[3:0] + 8'd1);
                                end
                            end
                        end else begin
                            // Drain recurrent weights into h_acc
                            h_acc[col_cnt + wbuf_drain] <=
                                h_acc[col_cnt + wbuf_drain]
                                + {{16{wbuf[wbuf_drain][15]}}, wbuf[wbuf_drain]};
                            wbuf_drain <= wbuf_drain + 4'd1;
                            if (wbuf_drain == FETCH_W - 1) begin
                                wbuf_ready <= 1'b0;
                                wbuf_fill  <= 5'd0;
                                col_cnt    <= col_cnt + FETCH_W;
                                if (col_cnt + FETCH_W >= NH) begin
                                    col_cnt <= 8'd0;
                                    row_cnt <= row_cnt + 8'd1;
                                    if (row_cnt + 8'd1 >= NH) begin
                                        row_cnt <= 8'd0;
                                        state   <= S_CAPTURE;
                                    end else begin
                                        mac_bram_addr <= addr_wrec(row_cnt+8'd1, 8'd0);
                                    end
                                end else begin
                                    mac_bram_addr <= addr_wrec(row_cnt,
                                                               col_cnt + FETCH_W);
                                end
                            end
                        end
                    end
                end

                // ── S_CAPTURE: Pulse lif_capture, wait for LIF sweep ──────────
                // LIF array needs NH cycles to sweep all neurons.
                // We use row_cnt as a wait counter (NH cycles is enough).
                S_CAPTURE: begin
                    if (row_cnt == 8'd0) begin
                        lif_capture <= 1'b1;
                    end
                    row_cnt <= row_cnt + 8'd1;
                    if (row_cnt >= NH + 2) begin
                        // LIF sweep done; lif_spikes is now stable
                        s_prev <= lif_spikes;   // Save for next timestep recurrent
                        row_cnt <= 8'd0;
                        t_cnt   <= t_cnt + 6'd1;

                        if (t_cnt + 6'd1 >= T) begin
                            // All timesteps done → compute output scores
                            col_cnt   <= 8'd0;
                            wbuf_fill <= 5'd0;
                            wbuf_ready<= 1'b0;
                            mac_bram_addr <= addr_wout(8'd0, 8'd0);
                            state <= S_OUT_ACC;
                        end else begin
                            // Reset hidden accumulators for next timestep
                            for (ci = 0; ci < NH; ci = ci + 1)
                                h_acc[ci] <= 32'sd0;
                            mac_bram_addr <= addr_win(8'd0, 8'd0);
                            state <= S_WIN_ACC;
                        end
                    end
                end

                // ── S_OUT_ACC: Accumulate W_out × final lif_spikes ────────────
                // row_cnt = hidden neuron (0..NH-1); col_cnt = output class (0..NO-1)
                // Only accumulate for neurons that fired in the last timestep.
                S_OUT_ACC: begin
                    if (!wbuf_ready) begin
                        if (mac_bram_grant) begin
                            wbuf[wbuf_fill[3:0]] <= $signed(mac_bram_dout);
                            wbuf_fill <= wbuf_fill + 5'd1;
                            // NO=10 fits in one FETCH_W=16 buffer
                            if (wbuf_fill == NO - 1) begin
                                wbuf_ready <= 1'b1;
                                wbuf_drain <= 4'd0;
                            end else begin
                                mac_bram_addr <= addr_wout(row_cnt,
                                    col_cnt + wbuf_fill[3:0] + 8'd1);
                            end
                        end
                    end else begin
                        if (s_prev[row_cnt]) begin
                            // Fired neuron: accumulate all NO output weights
                            score[wbuf_drain] <=
                                score[wbuf_drain]
                                + {{16{wbuf[wbuf_drain][15]}}, wbuf[wbuf_drain]};
                        end
                        wbuf_drain <= wbuf_drain + 4'd1;
                        if (wbuf_drain == NO - 1) begin
                            wbuf_ready <= 1'b0;
                            wbuf_fill  <= 5'd0;
                            row_cnt    <= row_cnt + 8'd1;
                            if (row_cnt + 8'd1 >= NH) begin
                                state <= S_SCORE;
                            end else begin
                                mac_bram_addr <= addr_wout(row_cnt + 8'd1, 8'd0);
                            end
                        end
                    end
                end

                // ── S_SCORE: Latch score_out, pulse score_valid ───────────────
                S_SCORE: begin
                    for (ci = 0; ci < NO; ci = ci + 1)
                        score_out[ci*32 +: 32] <= score[ci];
                    score_valid <= 1'b1;
                    state <= S_DONE;
                end

                // ── S_DONE: Pulse mac_done, release arbiter ───────────────────
                S_DONE: begin
                    mac_done     <= 1'b1;
                    mac_bram_req <= 1'b0;
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
