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
reg [7:0] wr_ptr;
reg [7:0] rd_ptr;

 
always @(posedge clk or negedge rst) begin
if (~rst) begin
wr_ptr <= 8'd0;
end 
else if (wr_en && !full) begin
mem[wr_ptr[6:0]] <= din;  
wr_ptr <= wr_ptr + 1'b1;
end
end


always @(posedge clk or negedge rst) begin
if (~rst) begin
rd_ptr <= 8'd0;
dout   <= 16'd0;
end 
else if (rd_en && !empty) begin
dout   <= mem[rd_ptr[6:0]]; 
rd_ptr <= rd_ptr + 1'b1;
end
end


assign empty = (wr_ptr == rd_ptr);

  
assign full  = (wr_ptr[6:0] == rd_ptr[6:0]) &&
                 (wr_ptr[7]   != rd_ptr[7]);

endmodule 
