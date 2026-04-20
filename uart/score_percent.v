`timescale 1ns / 1ps

module score_percent #(
    parameter SCORE_WIDTH = 17,
    parameter PERCENT_BITS = 7
)(
    input  wire signed [SCORE_WIDTH-1:0] score_in,
    output reg  [PERCENT_BITS-1:0] percent_out
);
    wire signed [SCORE_WIDTH+6:0] scaled;
    assign scaled = score_in * 100;

    always @(*) begin
        if (score_in[SCORE_WIDTH-1]) begin
            percent_out = {PERCENT_BITS{1'b0}};
        end else begin
            if (scaled[SCORE_WIDTH+6:8] > 100)
                percent_out = 7'd100;
            else
                percent_out = scaled[SCORE_WIDTH+6:8];
        end
    end
endmodule
