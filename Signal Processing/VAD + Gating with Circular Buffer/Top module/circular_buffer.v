module circular_buffer #(
    parameter BUFFER_SIZE         = 24000,
    parameter ADDR_WIDTH          = 15,
    parameter PRE_TRIGGER_SAMPLES = 3200
)(  
    input  wire clk,
    input  wire rst_n,
    input  wire [15:0] data_in,
    input  wire sample_valid,
    input  wire rd_en,
    input  wire pre_trig_rewind,
    output reg  [15:0] data_out,
    output wire data_valid,
    output wire buffer_full
);
    reg [15:0] mem [0:BUFFER_SIZE-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    parameter [ADDR_WIDTH-1:0] REWIND_OFFSET = BUFFER_SIZE - PRE_TRIGGER_SAMPLES;

    // Write pointer: advances at 16kHz
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_ptr <= {ADDR_WIDTH{1'b0}};
        else if (sample_valid) begin
            mem[wr_ptr] <= data_in;
            wr_ptr <= (wr_ptr == BUFFER_SIZE - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
        end
    end

    // Read pointer: advances at 100MHz when rd_en=1
    // Rewind jumps pointer back by PRE_TRIGGER_SAMPLES
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr    <= {ADDR_WIDTH{1'b0}};
            data_out  <= 16'd0;
        end else begin
            if (pre_trig_rewind) begin
                if (wr_ptr >= PRE_TRIGGER_SAMPLES[ADDR_WIDTH-1:0])
                    rd_ptr <= wr_ptr - PRE_TRIGGER_SAMPLES[ADDR_WIDTH-1:0];
                else
                    rd_ptr <= wr_ptr + REWIND_OFFSET;
            end else if (rd_en) begin
                data_out <= mem[rd_ptr];
                rd_ptr <= (rd_ptr == BUFFER_SIZE - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
            end
        end
    end

    // Combinational valid: high immediately when rd_en is asserted & not rewinding
    assign data_valid = rd_en && !pre_trig_rewind;
    
    // Full flag: wraps comparison
    wire [ADDR_WIDTH-1:0] wr_ptr_next = (wr_ptr == BUFFER_SIZE - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
    assign buffer_full = (wr_ptr_next == rd_ptr);
endmodule
