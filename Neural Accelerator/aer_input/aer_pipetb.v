module aer_pipetb();
  reg clk;
  reg rst_n;
  reg [23:0]data;
  reg aer_valid;

  wire [3:0]channel_Id;
  wire [19:0] timestamp;
  wire timestamp_valid;
  wire fifo_full;
  wire fifo_empty;

  aer_pipeline dut (
    .clk(clk),
    .rst_n(rst_n),
    .data(data),
    .aer_valid(aer_valid),
    .channel_Id(channel_Id),
    .timestamp(timestamp),
    .timestamp_valid(timestamp_valid),
    .fifo_full(fifo_full),
    .fifo_empty(fifo_empty)
  );
  
  integer i;
  
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end
  
  initial begin
  rst_n = 1'b0;
  #10;
  rst_n = 1;
  #10;
  data = 24'hA12345;
  aer_valid = 1;
  #100;
  aer_valid = 0;
  #100;
  
  
  for (i=0;i<=24'hFFFFFF;i=i+1) begin
  aer_valid = 1;
  #10;
  aer_valid = 0;
  data <= i;
  i = i + 24'h0000f0;
  #10;
  end
  
  
  rst_n = 1'b0;
  #10;
  rst_n = 1;
  #10;
  data = 24'hA22245;
  aer_valid = 1;
  #100;
  aer_valid = 0;
  #100000000;
  
  end
endmodule
