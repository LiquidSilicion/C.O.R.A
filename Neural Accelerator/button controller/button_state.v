
module button_state(
    input wire clk,
    input wire reset_n,
    input wire button_pressed,
    input wire wake_word_detected,
    
    output reg [1:0] aer_mode,       // 00=idle, 01=training, 10=command
    output reg clear_buffers,
    output reg start_processing,
    output reg [6:0] window_length
);
endmodule
