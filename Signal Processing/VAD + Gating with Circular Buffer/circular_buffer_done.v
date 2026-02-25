module circular_buffer #(
    parameter BUFFER_SIZE= 24000,
    parameter ADDR_WIDTH = 15,
    parameter PRE_TRIGGER_SAMPLES = 3200
)(  
    input  wire clk,
    input  wire rst_n,
    input  wire [15:0]data_in,
    input  wire sample_valid,
    input  wire rd_en,
    input  wire pre_trig_rewind,
    output reg  [15:0]data_out,
    output reg  data_valid,
    output wire buffer_full
);

    reg [15:0] mem [0:BUFFER_SIZE-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    parameter [ADDR_WIDTH-1:0] REWIND_OFFSET = BUFFER_SIZE - PRE_TRIGGER_SAMPLES;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
        end else if (sample_valid) begin
            mem[wr_ptr] <= data_in;
            wr_ptr <= (wr_ptr == BUFFER_SIZE - 1) ? {ADDR_WIDTH{1'b0}}: wr_ptr + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr    <= {ADDR_WIDTH{1'b0}};
            data_out  <= 16'd0;
            data_valid<= 1'b0;
        end else begin
            data_valid <= 1'b0;

            if (pre_trig_rewind) begin

                if (wr_ptr >= PRE_TRIGGER_SAMPLES[ADDR_WIDTH-1:0])
                    rd_ptr <= wr_ptr - PRE_TRIGGER_SAMPLES[ADDR_WIDTH-1:0];
                else
                    rd_ptr <= wr_ptr + REWIND_OFFSET;
            end else if (rd_en) begin
                data_out   <= mem[rd_ptr];
                data_valid <= 1'b1;
                rd_ptr <= (rd_ptr == BUFFER_SIZE - 1) ? {ADDR_WIDTH{1'b0}}
                                                       : rd_ptr + 1'b1;
            end
        end
    end
    
    wire [ADDR_WIDTH-1:0] wr_ptr_next =
        (wr_ptr == BUFFER_SIZE - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;

    assign buffer_full = (wr_ptr_next == rd_ptr);

endmodule
