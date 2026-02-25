module sp_pipeline #(
    
    
)(
    input wire clk,
    input wire rst_n,
    input wire data_valid,
    input wire [15:0]data_in,
    output reg data_out);
    
    parameter WAIT_DATA =4'b0000;
    parameter PREEMPHASIS = 4'b0001;
    parameter FILTER_BANK = 4'b0010;
    parameter IHC = 4'b0011;
    parameter LIF = 4'b0100;
    parameter AER = 4'b0101;
    
    
    reg [3:0]state, next_state;
    // I2S  flags and registers
    reg speech_valid;
    reg [15:0]i2s_data;
    
    //VAD+circular buffer flags and registers
    reg [15:0]circ_buffer_output;
    reg circ_buffer_ready;
    reg [15:0]i2s_data_in;
    reg i2s_data_ready;
    reg vad_audio_valid;
    reg vad_speech_valid;
    reg vad_raw;
    reg buffer_state;
    
    // Pre Emphasis
    reg pe_done;
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
    
    i2s_dummy i2s_dut(
     .clk(clk),
     .rst_n(rst_n),
     .data_ready(speech_valid),
     .data_out(i2s_data_out));
    
    vad_buffer_dummy( 
     .clk(clk),
     .rst_n(rst_n),
     .i2s_data_in(i2s_data_in),
     .i2s_valid(i2s_data_ready),
     .audio_out(),
     .audio_valid(),
     .speech_valid(speech_valid),
     .vad_raw(vad_raw),
     .buf_state(buffer_state));

    
    always@(posedge clk or negedge rst_n)
        if(!rst_n) begin
            data_out <= 0;
            speech_valid <= 0;
            i2s_data <= 0;
            circ_buffer_output <= 0;
            circ_buffer_ready <= 0;
        end else begin
            case(state)
                WAIT_DATA:
                if(speech_valid)begin
                    i2s_data <= data_in;
                end
                endcase   
end
endmodule
