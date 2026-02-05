
module aer_pipetb(
  reg clk,
  reg rst_n,
  reg [23:0]in,
  reg aer_valid,

  wire [3:0]channel_Id,
  wire [19:0] timestamp,
  wire timestamp_valid,
  wire fifo_full,
  wire fifo_empty);

  aer_pipeline dut (
    .clk(clk),
    .rst_n(rst_n),
    .in(in),
    .aer_valid(aer_valid),
    .channel_Id(channel_Id),
    .timestamp(timestamp),
    .timestamp_valid(timestamp_valid),
    .fifo_full(fifo_full),
    .fifo_empty(fifo_empty)
  );
  
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end
  
  initial begin
  rst_n = 1'b0;
  #10;
  rst_n = 1;
  #10;
  in = 24'hA12345;
  aer_valid = 1;
  #100;
  aer_valid = 0;
  #100;
  
  rst_n = 1'b0;
  #10;
  rst_n = 1;
  #10;
  in = 24'hA22245;
  aer_valid = 1;
  #100;
  aer_valid = 0;
  #100;
  end
endmodule