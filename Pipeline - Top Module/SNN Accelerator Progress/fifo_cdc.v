// fifo_cdc.v - Fixed with Memory Initialization to remove X values
module fifo_cdc #(
    parameter DATA_WIDTH = 24,
    parameter DEPTH      = 64,
    parameter ADDR_WIDTH = 7
)(
    input wire clk,
    input wire rst,
    input wire wr_en,
    input wire rd_en,
    input wire [DATA_WIDTH-1:0] din,
    output reg  [DATA_WIDTH-1:0] dout,
    output wire full,
    output wire empty
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    // ✅ FIX: Initialize memory to 0 to prevent X propagation
    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1) begin
            mem[init_idx] = 0;
        end
    end

    reg [ADDR_WIDTH:0] wr_ptr_ext;
    reg [ADDR_WIDTH:0] rd_ptr_ext;

    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr_ext[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr_ext[ADDR_WIDTH-1:0];

    always @(posedge clk or negedge rst) begin
        if (!rst) wr_ptr_ext <= 0;
        else if (wr_en && !full) begin
            mem[wr_addr] <= din;
            wr_ptr_ext <= wr_ptr_ext + 1'b1;
        end
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            rd_ptr_ext <= 0;
            dout       <= 0;
        end else if (rd_en && !empty) begin
            dout       <= mem[rd_addr];
            rd_ptr_ext <= rd_ptr_ext + 1'b1;
        end
    end

    assign empty = (wr_ptr_ext == rd_ptr_ext);
    assign full  = (wr_ptr_ext == rd_ptr_ext + DEPTH);

endmodule
