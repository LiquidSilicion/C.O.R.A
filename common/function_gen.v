module inputtb();
  reg clk;
  reg rst_n;
  reg  [23:0] in;
  reg aer_valid;
  
  wire spike_detected;
  wire [3:0] channel_Id;
  wire [19:0] timestamp;
  wire timestamp_valid;
    
  input_from_aer dut (
    .clk(clk),
    .rst_n(rst_n),
    .in(in),
    .aer_valid(aer_valid),
    .spike_detected(spike_detected),
    .channel_Id(channel_Id),
    .timestamp(timestamp),
    .timestamp_valid(timestamp_valid)
  );
  
  integer i;
  
  
  initial begin
    clk = 0;
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
  
  for (i=0;i<=24'hFFFFFF;i=i+1) begin
  aer_valid = 1;
  #10;
  aer_valid = 0;
  in <= i;
  i = i + 24'h0f0f00;
  #10;
  end
  end
endmodule
