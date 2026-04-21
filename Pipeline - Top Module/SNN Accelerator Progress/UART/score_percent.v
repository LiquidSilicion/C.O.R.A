`timescale 1ns / 1ps
module score_percent #(
    parameter SCORE_WIDTH  = 17,
    parameter PERCENT_BITS = 7
)(
    input  wire signed [SCORE_WIDTH-1:0] score_in,
    output reg  [PERCENT_BITS-1:0]       percent_out
);
    always @(*) begin
        if (score_in[SCORE_WIDTH-1])
            percent_out = 7'd0;
        else if (score_in >= 10000)
            percent_out = 7'd100;
        else
            percent_out = score_in[SCORE_WIDTH-1:0] / 100;
    end
endmodule