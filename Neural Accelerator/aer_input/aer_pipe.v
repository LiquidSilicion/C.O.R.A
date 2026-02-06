module aer_pipeline(
  input clk,
  input rst_n,
  input [23:0]data,
  input aer_valid,

  output [3:0]channel_Id,
  output [19:0] timestamp,
  output timestamp_valid,
  output fifo_full,
  output fifo_empty);

  wire [23:0] fifo_dout;
  wire fifo_rd;
  wire spike_detected;
  
  assign fifo_rd = fifo_full;
  
  input_from_aer dut (
    .clk(clk),
    .rst_n(rst_n),
    .in(fifo_dout),
    .aer_valid(fifo_rd),
    .spike_detected(spike_detected),
    .channel_Id(channel_Id),
    .timestamp(timestamp),
    .timestamp_valid(timestamp_valid)
  );
  
  fifo dut_fifo (
    .clk(clk),
    .rst(rst_n),
    .rd_en(fifo_rd),
    .wr_en(!fifo_full),
    .din(data),
    .dout(fifo_dout),
    .full(fifo_full),
    .empty(fifo_empty)
  );

endmodule
