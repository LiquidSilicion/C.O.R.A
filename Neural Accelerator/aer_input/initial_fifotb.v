module fifotb();
  reg clk;
  reg rst;
  reg rd_en;
  reg wr_en;
  reg [23:0] din;
  wire  [23:0] dout;
  wire full;
  wire empty;
  
 integer i;
 
 
  fifo dut(
  .clk(clk),
  .rst(rst),
  .rd_en(rd_en),
  .wr_en(wr_en),
  .din(din),
  .dout(dout),
  .full(full),
  .empty(empty)
);

 initial begin
 clk =0;
 forever #5 clk = ~clk;
 end
 
 initial begin
 rst=0;
 #10
 rst=1;
 
 for (i=0;i<=24'hFFFFFF;i=i+1) begin
  #10;
  din <= i;
  i = i + 24'h0000f0;
  #10;
  end
  end
endmodule
