module aer_pipeline(
  input clk,
  input rst_n,
  input [23:0]in,
  input aer_valid,

  output [3:0]channel_Id,
  output [19:0] timestamp,
  output timestamp_valid,
  output fifo_full,
  output fifo_empty);

  wire [23:0] fifo_dout;
  wire fifo_rd;
  
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
  
  fifo dut_fifo (
    .clk(clk),
    .rst(rst_n),
    .rd_en(fifo_rd_en),
    .wr_en(aer_valid_in && !fifo_full),
    .din(aer_data_in),
    .dout(fifo_dout),
    .full(fifo_full),
    .empty(fifo_empty)
  );

  assign fifo_rd = ~fifo_empty;


endmodule
