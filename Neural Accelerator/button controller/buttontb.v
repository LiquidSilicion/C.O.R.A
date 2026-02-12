module button_statetb();
    reg clk;
    reg rst_n;
    reg spike_valid;
    reg button_pressed;
    reg clear_window;
    reg [3:0] channel_id;
    reg [19:0] aer_data;
    reg [3:0] training_counter;
    
    wire clear_buffers;
    wire start_processing;
    wire [6:0] window_length;
    wire [3:0] training_progress;
    wire system_ready;
    
    button_state dut(
       .clk(clk),
       .rst_n(rst_n),
       .spike_valid(spike_valid),
       .button_pressed(button_pressed),
       .clear_window(clear_window),
       .aer_data(aer_data),
       .channel_id(channel_id),
       .training_counter(training_counter),
       .clear_buffers(clear_buffers),
       .start_processing(start_processing),
       .start_processing(start_processing),
       .training_progress(training_progress),
       .system_ready(system_ready),
       .sys_state(),
       .int_state()
       );
    
    integer i;
    
    initial begin
    clk = 1'b0;
    forever #5 clk = ~clk; 
    end
    
    
    initial begin
    rst_n = 1'b0;
    
    #10;
    rst_n = 1'b1;
    
    for (i=0;i<=24'hFFFFFF;i=i+1) begin
    spike_valid = 1;
    #10;
    spike_valid = 0;
    aer_data <= i;
    i = i + 24'h0f0f00;
    #10;
    end
    end
endmodule
