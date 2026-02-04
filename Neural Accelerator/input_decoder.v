module input_from_aer();
  input clk,
  input rst_n,
  input wire [23:0]in,
  input aer_valid,
  
  
  output reg [3:0]channel_Id,
  output reg [19:0]timestamp;
  
  always@(posedge clk or negedge rst_n)
    channel_id <= in[23:20];
 	timestamp <= in[19:0];

endmodule
