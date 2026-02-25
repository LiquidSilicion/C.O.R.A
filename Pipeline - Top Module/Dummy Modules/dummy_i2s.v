module i2s_dummy(
    input wire clk,
    input wire rst_n,
    input wire i2s_valid,
    input wire data_valid,
    input wire [15:0] data_in,
    output reg i2s_data_ready,
    output reg [15:0] i2s_data_out,
    output reg [15:0] i2s_out_valid,
    output reg speech_valid
);

    reg data_stored;
    reg [15:0] stored_data;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            i2s_data_out <= 16'b0;
            i2s_data_ready <= 1'b0;
            data_stored <= 1'b0;
            stored_data <= 16'b0;
        end else begin
            if(!data_stored) begin
                i2s_data_ready <= 1'b0;
            end

            if(i2s_valid) begin
                stored_data <= data_in;
                data_stored <= 1'b1;
                i2s_data_ready <= 1'b1;
                i2s_data_out <= data_in;
                speech_valid <= 1'b1;
            end
        end
    end

endmodule
