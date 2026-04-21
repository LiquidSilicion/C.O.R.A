`timescale 1ns / 1ps
// =============================================================================
// Module  : s10_window_accumulator
// Purpose : CORA Stage 10 - 50 ms window accumulator @ 100 MHz
//
// Target  : AMD ZCU104 (XCZU7EV-2FFVC1156) @ 100 MHz
//
// ─── Timing ──────────────────────────────────────────────────────────────────
//  At 100 MHz, 50 ms = 5 000 000 cycles.
//  The WINDOW_CYCLES parameter is set to 5_000_000 by default.
//  Set WINDOW_CYCLES to a smaller value for simulation (e.g. 100).
// =============================================================================
module s10_window_accumulator #(
    parameter NI            = 16,           // Number of input channels
    parameter T             = 50,           // Time bins per window
    parameter WINDOW_CYCLES = 5_000_000,    // 50 ms at 100 MHz (was 10_000_000 @ 200MHz)
    parameter THRESH        = 8'd200        // Saturation ceiling for 8-bit counter
)(
    input  wire         clk,
    input  wire         reset_n,
    input  wire [19:0]  window_offset,
    input  wire         ts_abs_valid,
    input  wire [3:0]   spike_ch,
    input  wire         speech_valid,
    output reg          window_open,
    output reg          window_ready,
    output reg          rd_ping_sel,
    input  wire [10:0]  mac_rd_addr,
    output wire [7:0]   mac_rd_data
);

localparam WCNT_W = $clog2(WINDOW_CYCLES + 1);
reg [WCNT_W-1:0] win_cnt;
reg              wr_ping;

always @(posedge clk) begin
    if (!reset_n) begin
        win_cnt      <= {WCNT_W{1'b0}};
        wr_ping      <= 1'b0;
        window_open  <= 1'b0;
        window_ready <= 1'b0;
        rd_ping_sel  <= 1'b0;
    end else begin
        window_ready <= 1'b0;

        if (!speech_valid) begin
            win_cnt     <= {WCNT_W{1'b0}};
            window_open <= 1'b0;
        end else begin
            window_open <= 1'b1;

            if (win_cnt == WINDOW_CYCLES - 1) begin
                win_cnt      <= {WCNT_W{1'b0}};
                wr_ping      <= ~wr_ping;
                rd_ping_sel  <= wr_ping;
                window_ready <= 1'b1;
            end else begin
                win_cnt <= win_cnt + 1'b1;
            end
        end
    end
end

wire [5:0] bin_idx = window_offset[15:10];

localparam [1:0] ST_IDLE = 2'd0, ST_READ = 2'd1, ST_WRITE = 2'd2;
reg [1:0]  acc_state;
reg [10:0] bram_addra;
reg        bram_ena;
reg        bram_wea;
reg [7:0]  bram_dina;
wire [7:0] bram_douta;
reg [10:0] pending_addr;

always @(posedge clk) begin
    if (!reset_n) begin
        acc_state    <= ST_IDLE;
        bram_addra   <= 11'd0;
        bram_ena     <= 1'b0;
        bram_wea     <= 1'b0;
        bram_dina    <= 8'd0;
        pending_addr <= 11'd0;
    end else begin
        bram_ena <= 1'b0;
        bram_wea <= 1'b0;

        case (acc_state)
            ST_IDLE: begin
                if (ts_abs_valid && speech_valid && spike_ch < NI && bin_idx < T) begin
                    pending_addr <= {wr_ping, spike_ch, bin_idx};
                    bram_addra   <= {wr_ping, spike_ch, bin_idx};
                    bram_ena     <= 1'b1;
                    bram_wea     <= 1'b0;
                    acc_state    <= ST_READ;
                end
            end

            ST_READ: begin
                bram_addra <= pending_addr;
                bram_ena   <= 1'b1;
                bram_wea   <= 1'b1;
                bram_dina  <= (bram_douta == 8'hFF) ? 8'hFF : bram_douta + 8'd1;
                acc_state  <= ST_WRITE;
            end

            ST_WRITE: begin
                acc_state <= ST_IDLE;
            end

            default: acc_state <= ST_IDLE;
        endcase
    end
end

window_acc u_win_bram (
    .clka  (clk),
    .ena   (bram_ena),
    .wea   (bram_wea),
    .addra (bram_addra),
    .dina  (bram_dina),
    .douta (bram_douta),
    .clkb  (clk),
    .enb   (1'b1),
    .web   (1'b0),
    .addrb (mac_rd_addr),
    .dinb  (8'd0),
    .doutb (mac_rd_data)
);

endmodule