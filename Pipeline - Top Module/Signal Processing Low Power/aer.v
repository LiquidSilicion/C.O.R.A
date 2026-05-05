`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/30/2026 12:05:55 PM
// Design Name: 
// Module Name: aer
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


module aer_encoder (
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_en,
    input  wire [15:0] spike,
    output reg  [23:0] data,
    output reg         aer_valid,
    input  wire        aer_ready
);

    // ----------------------------------------------------------
    //  Timestamp - increments per sample_en (16kHz)
    // ----------------------------------------------------------
    reg [19:0] timestamp;
        reg       found;
        reg [3:0] ch_id;
        wire send_fire = found && (aer_ready || !aer_valid);
    always @(posedge clk) begin
        if (rst)
            timestamp <= 20'd0;
        else if (sample_en)
            timestamp <= timestamp + 1'd1;
    end

    // ----------------------------------------------------------
    //  Timestamp latch - FIX 3: removed +1
    //  Captures timestamp when spike arrives
    //  sample_en fires → latch current timestamp
    // ----------------------------------------------------------
    reg [19:0] ts_latch;
    always @(posedge clk) begin
        if (rst)
            ts_latch <= 20'd0;
        else if (sample_en)
            ts_latch <= timestamp;   // FIX 3: was timestamp+1
    end

    // ----------------------------------------------------------
    //  FIX 1 - Edge detection
    //  Only capture RISING EDGE of each spike bit
    //  Protects against held-high spike inputs
    //  In real LIF pipeline spikes are 1-cycle anyway
    // ----------------------------------------------------------
    reg [15:0] spike_prev;
    always @(posedge clk) begin
        if (rst) 
            spike_prev <= 16'h0;
        else
            spike_prev <= spike;
    end

    wire [15:0] spike_new = spike & ~spike_prev;  // rising edge only

    // ----------------------------------------------------------
    //  FIX 2 - Accumulator uses spike_new
    //  OR in only NEW spike edges - not raw spike level
    //  Clear bit only after successful transmission
    // ----------------------------------------------------------
    reg [15:0] spike_reg;
    always @(posedge clk) begin
        if (rst) begin
            spike_reg <= 16'h0;
        end else begin
            spike_reg <= spike_reg | spike_new;  // FIX 2
            if (send_fire)
                spike_reg[ch_id] <= 1'b0;
        end
    end

    // ----------------------------------------------------------
    //  Priority encoder - find lowest set bit
    // ----------------------------------------------------------
    always @(*) begin
        found = 1'b0; ch_id = 4'd0;
        if      (spike_reg[0])  begin found=1'b1; ch_id=4'd0;  end
        else if (spike_reg[1])  begin found=1'b1; ch_id=4'd1;  end
        else if (spike_reg[2])  begin found=1'b1; ch_id=4'd2;  end
        else if (spike_reg[3])  begin found=1'b1; ch_id=4'd3;  end
        else if (spike_reg[4])  begin found=1'b1; ch_id=4'd4;  end
        else if (spike_reg[5])  begin found=1'b1; ch_id=4'd5;  end
        else if (spike_reg[6])  begin found=1'b1; ch_id=4'd6;  end
        else if (spike_reg[7])  begin found=1'b1; ch_id=4'd7;  end
        else if (spike_reg[8])  begin found=1'b1; ch_id=4'd8;  end
        else if (spike_reg[9])  begin found=1'b1; ch_id=4'd9;  end
        else if (spike_reg[10]) begin found=1'b1; ch_id=4'd10; end
        else if (spike_reg[11]) begin found=1'b1; ch_id=4'd11; end
        else if (spike_reg[12]) begin found=1'b1; ch_id=4'd12; end
        else if (spike_reg[13]) begin found=1'b1; ch_id=4'd13; end
        else if (spike_reg[14]) begin found=1'b1; ch_id=4'd14; end
        else if (spike_reg[15]) begin found=1'b1; ch_id=4'd15; end
    end

    // ----------------------------------------------------------
    //  Handshake - send when found and bus available
    // ----------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            data      <= 24'd0;
            aer_valid <= 1'b0;
        end else begin
            if (send_fire) begin
                data      <= {ch_id, ts_latch};
                aer_valid <= 1'b1;
            end else if (aer_ready && aer_valid && !found) begin
                // FIX 4: only deassert when nothing left to send
                aer_valid <= 1'b0;
            end
        end
    end

endmodule
