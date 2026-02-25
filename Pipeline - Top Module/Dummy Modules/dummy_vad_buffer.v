module vad_buffer_dummy(
    input wire clk,
    input wire rst_n,
    input wire data_valid,
    input wire i2s_data_in,
    input wire i2s_data_ready,
    output reg vad_out,
    output reg vad_valid,
    output reg speech_valid,
    output reg vad_raw,
    output reg buffer_state);
    
    always@(posedge clk or negedge rst_n)
        if(!rst_n)begin
            vad_out<=0;
        end else begin
            if(data_valid)begin
                vad_out<= i2s_data_in;
            end
     end
endmodule
