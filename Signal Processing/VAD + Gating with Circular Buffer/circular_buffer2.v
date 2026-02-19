module circular_buffer #(
    parameter BUFFER_SIZE = 24000
)(
    input wire clk,
    input wire rst_n,
    input wire [15:0] data_in,
    input wire sample_valid,
    
    output reg [15:0] data_out,
    output reg buffer_full
);

    localparam ADDR_WIDTH = 15;
    
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [15:0] circular_buffer [0:BUFFER_SIZE-1];
    
    reg wrap_flag;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            buffer_full <= 0;
            wrap_flag <= 0;
        end else if (sample_valid) begin
            circular_buffer[wr_ptr] <= data_in;
            
            if (wr_ptr == BUFFER_SIZE - 1) begin
                wr_ptr <= 0;
                wrap_flag <= 1;
            end else begin
                wr_ptr <= wr_ptr + 1;
            end
            
            if (wr_ptr == BUFFER_SIZE - 1 && rd_ptr == 0) begin
                buffer_full <= 1;
                rd_ptr <= rd_ptr + 1;
            end
            else if (wr_ptr + 1 == rd_ptr) begin
                buffer_full <= 1;
                rd_ptr <= rd_ptr + 1;
            end
            else begin
                buffer_full <= 0;
            end
            
            if (rd_ptr == BUFFER_SIZE) begin
                rd_ptr <= 0;
            end
        end
    end
    
    always @(*) begin
        data_out = circular_buffer[rd_ptr];
    end

endmodule
