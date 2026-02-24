module sp_pipeline(
    input wire clk,
    input wire rst_n,
    input wire data_valid,
    input wire data_in,
    output reg data_out);
    
    parameter IDLE=1'b00;
    parameter STATE_1 =1'b01;
    
    
    reg [2:0]state;
    // I2S  flags and registers
    reg speech_valid;
    reg [15:0]i2s_data;
    
    //VAD+circular buffer flags and registers
    reg [15:0]circ_buffer_output;
    reg circ_buffer_ready;
    reg o;
    
    // Pre Emphasis
    reg pm_ready;
    reg [23:0]y_out;
    
    //Filter Bank
    reg [16:0]filter_output;
    reg filter_bank_ready;
    
    //IHC Model
    reg ihc_output;
    
    //LIF Encoder
    
    //AER Packetizer
    
    //AER Depacketizer + FIFO
    
    //Window Accumulator
    
    //MAC+LIF
    
    //Output
    
    always@(posedge clk or negedge rst_n)
        if(!rst_n) begin
            data_out <= 0;
        end else begin
            
end
endmodule
