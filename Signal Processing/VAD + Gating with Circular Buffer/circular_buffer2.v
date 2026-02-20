module circular_buffer #(
    parameter BUFFER_SIZE = 24000,
    parameter ADDR_WIDTH = $clog2(BUFFER_SIZE)  // Automatically calculate width
)(
    input wire clk,
    input wire rst_n,
    input wire [15:0] data_in,
    input wire write_en,      // Renamed from sample_valid for clarity
    input wire read_en,       // Added read enable
    
    output reg [15:0] data_out,
    output reg buffer_full,
    output reg buffer_empty   // Added empty flag
);

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [15:0] circular_buffer [0:BUFFER_SIZE-1];
    
    reg [ADDR_WIDTH:0] fifo_count;  // Track number of elements
    
    // Track number of elements in buffer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_count <= 0;
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            case ({write_en, read_en})
                2'b10: if (fifo_count < BUFFER_SIZE) begin  // Write only
                    fifo_count <= fifo_count + 1;
                    wr_ptr <= (wr_ptr == BUFFER_SIZE-1) ? 0 : wr_ptr + 1;
                end
                2'b01: if (fifo_count > 0) begin  // Read only
                    fifo_count <= fifo_count - 1;
                    rd_ptr <= (rd_ptr == BUFFER_SIZE-1) ? 0 : rd_ptr + 1;
                end
                2'b11: if (fifo_count > 0 && fifo_count < BUFFER_SIZE) begin  // Write and read
                    wr_ptr <= (wr_ptr == BUFFER_SIZE-1) ? 0 : wr_ptr + 1;
                    rd_ptr <= (rd_ptr == BUFFER_SIZE-1) ? 0 : rd_ptr + 1;
                    // fifo_count stays the same
                end
                default: ; // No change
            endcase
        end
    end
    
    // Write operation
    always @(posedge clk) begin
        if (write_en && fifo_count < BUFFER_SIZE) begin
            circular_buffer[wr_ptr] <= data_in;
        end
    end
    
    // Read operation (combinational for immediate output)
    always @(*) begin
        if (fifo_count > 0)
            data_out = circular_buffer[rd_ptr];
        else
            data_out = 16'h0000;  // Default value when empty
    end
    
    // Status flags
    assign buffer_full = (fifo_count == BUFFER_SIZE);
    assign buffer_empty = (fifo_count == 0);

endmodule
