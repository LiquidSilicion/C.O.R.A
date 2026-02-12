module button_led_state(
    input wire clk,
    input wire rst_n,
    input wire spike_valid,
    input wire button_pressed,
    input wire clear_window,
    input wire [3:0] channel_id,
    input wire [3:0] training_counter,
    
    output reg [4:0]led,
    output reg clear_buffers,
    output reg start_processing,
    output reg [6:0] window_length,
    output reg [3:0] training_progress,
    output reg system_ready
);

    localparam SYS_IDLE           = 3'd0;
    localparam SYS_TRAINING       = 3'd1;
    localparam SYS_TRAIN_PROCESS  = 3'd2;
    localparam SYS_READY          = 3'd3;
    localparam SYS_COMMAND_ACTIVE = 3'd4;
    
    reg [2:0] sys_state;
    reg [3:0] examples_collected;
   
    localparam INT_WAIT    = 2'd0;
    localparam INT_RECORD  = 2'd1;
    localparam INT_PROCESS = 2'd2;
    
    reg [1:0] int_state;
    
    reg [15:0] utterance_bins [0:299];
    reg [8:0] utterance_length;
    
    reg [799:0] training_examples [0:14];
    
    reg example_ready;
    reg [799:0] example_window;
    
    reg bin_timer_tick;
    reg wake_word_detected;
    reg command_complete;

    integer i;
    integer src_index;

    reg [7:0] bin_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bin_counter <= 8'd0;
            bin_timer_tick <= 1'b0;
        end
        else begin
            if (bin_counter == 8'd99) 
            begin
                bin_counter <= 8'd0;
                bin_timer_tick <= 1'b1;
            end
            else begin
                bin_counter <= bin_counter + 1;
                bin_timer_tick <= 1'b0;
            end
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sys_state <= SYS_IDLE;
            examples_collected <= 4'b0;
            system_ready <= 1'b0;
            led <= 1'b0;
        end
        else begin
            case (sys_state)
                SYS_IDLE: begin
                    if (button_pressed) begin
                        sys_state <= SYS_TRAINING;
                        examples_collected <= 4'b0;
                        led <= 1'b0;
                    end
                end
                
                SYS_TRAINING: begin
                    if (example_ready) begin
                        training_examples[examples_collected] <= example_window;
                        examples_collected <= examples_collected + 1'b1;
                        led <= examples_collected + 1'b1;

                        if (examples_collected == 4'd14) 
                        begin
                            sys_state <= SYS_TRAIN_PROCESS;
                        end
                    end
                end
                
                SYS_TRAIN_PROCESS: begin
                    // to be replaced with actual interface logic
                    sys_state <= SYS_READY;
                    system_ready <= 1'b1;
                end
                
                SYS_READY: begin
                    if (wake_word_detected) begin
                        sys_state <= SYS_COMMAND_ACTIVE;
                    end
                end
                
                SYS_COMMAND_ACTIVE: begin
                    if (command_complete) begin
                        sys_state <= SYS_READY;
                    end
                end
                
                default: begin
                    sys_state <= SYS_IDLE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_state <= INT_WAIT;
            example_ready <= 1'b0;
            utterance_length <= 9'b0;
            example_window <= 800'b0;
        end
        else begin
            if (sys_state == SYS_TRAINING) begin
                case (int_state)
                    INT_WAIT: begin
                        example_ready <= 1'b0;
                        if (button_pressed) begin
                            int_state <= INT_RECORD;
                            utterance_length <= 9'b0;
                            for (i = 0; i < 300; i = i + 1) begin
                                utterance_bins[i] <= 16'b0;
                            end
                        end
                    end
                    
                    INT_RECORD: begin
                        if (spike_valid) begin
                            utterance_bins[utterance_length] <= 
                                utterance_bins[utterance_length] | (16'b1 << channel_id);
                        end
                        
                        if (bin_timer_tick) begin
                            utterance_length <= utterance_length + 1'b1;
                        end
                        
                        if (!button_pressed) begin
                            int_state <= INT_PROCESS;
                        end
                    end
                    
                    INT_PROCESS: begin
                        for (i = 0; i < 50; i = i + 1) begin
                            src_index = (i * utterance_length) / 50;
                            if (src_index < 300) begin
                                example_window[i*16 +: 16] <= utterance_bins[src_index];
                            end
                            else begin
                                example_window[i*16 +: 16] <= 16'b0;
                            end
                        end
                        example_ready <= 1'b1;
                        int_state <= INT_WAIT;
                    end
                    
                    default: begin
                        int_state <= INT_WAIT;
                    end
                endcase
            end
            else begin
                int_state <= INT_WAIT;
                example_ready <= 1'b0;
            end
        end
    end
    
   
    always @(*) begin
        training_progress = examples_collected;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wake_word_detected <= 1'b0;
            command_complete <= 1'b0;
        end
        else begin

            wake_word_detected <= 1'b0;
            command_complete <= 1'b0;
        end
    end

endmodule
