module input_from_aer(
  input clk,
  input rst_n,
  input wire [23:0] in,
  input aer_valid,
  
  output reg spike_detected,
  output reg [3:0] channel_Id,
  output reg [19:0] timestamp,
  output reg timestamp_valid
);
  
  always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      channel_Id <= 4'b0;
      timestamp <= 20'b0;
      spike_detected <= 1'b0;
      timestamp_valid <= 1'b0;
    end
    else begin
      if (aer_valid) begin
        channel_Id <= in[23:20];
        timestamp <= in[19:0];
        spike_detected <= 1'b1;
        timestamp_valid <= 1'b1;
        $display("AER input is %d: %d", channel_Id, timestamp);
      end
      else begin
        spike_detected <= 1'b0;
        timestamp_valid <= 1'b0;
      end
    end
  end
endmodule
