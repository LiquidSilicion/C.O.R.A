`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: spike_readback
// Purpose: Reads the window accumulator BRAM after window_ready pulse and
//          converts 8-bit saturation counts to a binary spike bus for the MAC.
//
// The window accumulator BRAM address is:
//   {ping_sel[0], ch[3:0], bin[5:0]}  →  11 bits
//   But only bins 0..49 (T=50) are valid, so ch*T + bin maps to:
//   win_spikes[ch*T + bin] = (rd_data > THRESH)
//
// This module is driven by win_ready and must complete before mac_start.
// At 200 MHz with 800 addresses: 800 cycles = 4 µs.
// The sequencer in the top module currently pulses mac_start immediately after
// win_ready. Add a one-cycle delay or use spike_rb_done as the mac_start trigger.
//
// NOTE: rd_ping is the ping_sel that was just written (stable after win_ready).
//       The accumulator latches rd_ping_sel at EMIT state.
//////////////////////////////////////////////////////////////////////////////////

module spike_readback #(
    parameter NI     = 16,    // Number of input channels
    parameter T      = 50,    // Bins per window
    parameter THRESH = 8'd1   // Minimum count to declare a spike
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,       // win_ready pulse
    input  wire              rd_ping,     // Which BRAM half to read
    output reg  [10:0]       rd_addr,     // To window accumulator BRAM port B
    input  wire [7:0]        rd_data,     // From window accumulator BRAM port B
    output reg  [NI*T-1:0]  win_spikes,  // Packed spike bus for MAC engine
    output reg               done         // Readback complete
);

    localparam TOTAL = NI * T;   // 800 addresses

    reg         active;
    reg [9:0]   cnt;        // 0..799
    reg [3:0]   ch;         // Current channel
    reg [5:0]   bin;        // Current bin

    always @(posedge clk) begin
        if (!rst_n) begin
            active     <= 1'b0;
            cnt        <= 10'd0;
            ch         <= 4'd0;
            bin        <= 6'd0;
            rd_addr    <= 11'd0;
            win_spikes <= {NI*T{1'b0}};
            done       <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !active) begin
                active  <= 1'b1;
                cnt     <= 10'd0;
                ch      <= 4'd0;
                bin     <= 6'd0;
                // Issue first address (BRAM read latency = 1 cycle)
                rd_addr <= {rd_ping, 4'd0, 6'd0};
            end

            if (active) begin
                // One cycle after issuing rd_addr, rd_data is valid.
                // We registered rd_addr last cycle and rd_data is valid now.
                // Because of 1-cycle BRAM latency: on cycle N we issue addr,
                // on cycle N+1 we capture. So we capture at cnt >= 1.
                if (cnt >= 10'd1) begin
                    // Reconstruct channel and bin from previous address
                    // Previous ch/bin is (cnt-1):
                    // We need to delay ch/bin by 1. Use a simple trick:
                    // capture at cnt = 1..800, corresponding to addr 0..799.
                    win_spikes[ch * T + bin] <= (rd_data >= THRESH) ? 1'b1 : 1'b0;
                end

                if (cnt < TOTAL) begin
                    // Advance ch/bin for NEXT read (pipeline the address)
                    if (bin == T - 1) begin
                        bin <= 6'd0;
                        ch  <= ch + 4'd1;
                    end else begin
                        bin <= bin + 6'd1;
                    end
                    rd_addr <= {rd_ping, ch, bin};   // Issue next read
                    cnt <= cnt + 10'd1;
                end else begin
                    // All addresses issued; last data just captured
                    active <= 1'b0;
                    done   <= 1'b1;
                end
            end
        end
    end

endmodule
