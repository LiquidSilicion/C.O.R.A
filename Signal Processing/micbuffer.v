module fifo(
  input clk,
  input rst,
  input rd_en,
  input wr_en,
  input [15:0] din,
  output [15:0] dout,
  output full,
  output empty
);
  //memory
  reg[15:0] mem [127:0];
  
  //pointers
  reg[6:0] wr_ptr;
  reg[6:0] rd_ptr;
  
  always@(posedge clk or negedge rst)
    if(rst)
      begin
        wr_ptr <=0;
        else if(
