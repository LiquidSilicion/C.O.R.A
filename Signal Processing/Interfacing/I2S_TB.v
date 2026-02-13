`timescale 1ns / 1ps

module I2S_tb();
reg clk;
reg rst;
reg sd;

wire bclk;
wire lrclk;
wire [15:0] sample;
wire sample_valid;

I2S uut (
.clk(clk), 
.rst(rst), 
.sd(sd), 
.bclk(bclk), 
.lrclk(lrclk), 
.sample(sample), 
.sample_valid(sample_valid)
    );

initial begin
clk = 0;
forever #5 clk = ~clk;
end

integer i; 
integer k; 
reg [23:0] word;

initial begin
rst = 1;
sd = 0;
word = 0;
        
#100;
rst = 0; 
    

for (k = 1; k <= 23; k = k + 1) begin
            
           
word = {k[15:0], 8'h00};
wait(lrclk == 1);
wait(lrclk == 0);
            
            
@(negedge bclk);
sd = 0; 

for (i = 23; i >= 0; i = i - 1) begin
@(negedge bclk);
sd = word[i];
end
            
@(negedge bclk);
sd = 0;

@(posedge sample_valid);
$display("Time: %t | Sent: %h | Received: %h", $time, word[23:8], sample);
end

        
#50000; 
$display("Simulation Finished.");
$finish;
end

endmodule
