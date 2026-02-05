
module fifo(
  input clk,
  input rst,
  input rd_en,
  input wr_en,
  input [15:0] din,
  output reg [15:0] dout,
  output full,
  output empty
);

  reg [15:0] mem [127:0];
  
  reg [6:0] wr_ptr;
  reg [6:0] rd_ptr;

  // Write
  always @(posedge clk or negedge rst) begin
    if (~rst) begin
      wr_ptr <= 0;
    end 
    else if (wr_en && !full) begin
      mem[wr_ptr] <= din;
      wr_ptr <= wr_ptr + 1'b1;
    end
  end

  // Read
  always @(posedge clk or negedge rst) begin
    if (~rst) begin
      rd_ptr <= 0;
      dout   <= 0;
    end 
    else if (rd_en && !empty) begin
      dout   <= mem[rd_ptr];
      rd_ptr <= rd_ptr + 1'b1;
    end
  end

  assign empty = (wr_ptr == rd_ptr);
  assign full  = ((wr_ptr + 1'b1) == rd_ptr);

endmodule
