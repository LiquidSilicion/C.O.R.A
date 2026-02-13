`timescale 1ns / 1ps

module I2S(
input clk,
input rst,        
input sd,
output reg bclk = 0,
output reg lrclk = 1,
outpututput reg [15:0] sample = 0,
output reg sample_valid = 0
);

reg [6:0] clk_div = 0;
reg [5:0] bit_count = 0;
reg [23:0] shift_reg = 0;

always @(posedge clk or posedge rst) begin
if (rst) begin
clk_div <= 0;
bclk <= 0;
end else begin
if (clk_div == 49) begin 
clk_div <= 0;
bclk <= ~bclk;
end else begin
clk_div <= clk_div + 1;
end
end
end

wire bclk_rising = (clk_div == 49 && bclk == 0);

always @(posedge clk or posedge rst) begin
if (rst) begin
bit_count <= 0;
lrclk <= 1;
shift_reg <= 0;
sample <= 0;
sample_valid <= 0;
end else begin
sample_valid <= 0; 

if (bclk_rising) begin
shift_reg <= {shift_reg[22:0], sd};

if (bit_count == 63) begin
bit_count <= 0;
lrclk <= ~lrclk;
end else begin
bit_count <= bit_count + 1;
end

            
if (bit_count == 17 && lrclk == 0) begin
sample <= shift_reg[15:0];
sample_valid <= 1'b1;
end
end
end
end
endmodule
