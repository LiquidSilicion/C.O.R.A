module button_state(
    input wire clk,
    input wire rst_n,
    input wire spike_valid,
    input wire button_pressed,
    input wire clear_window,
    input wire [23:0] aer_data,
    input wire [3:0] training_counter,
    
    output reg [4:0] led,           // 5 LEDs for status
    output reg clear_buffers,
    output reg start_processing,
    output reg [3:0] training_progress,
    output reg system_ready
);

    localparam SYS_IDLE           = 3'd0;
    localparam SYS_TRAINING       = 3'd1;
    localparam SYS_TRAIN_PROCESS  = 3'd2;
    localparam SYS_READY          = 3'd3;
    localparam SYS_COMMAND_ACTIVE = 3'd4;
    
    reg [2:0] sys_state;
    reg [3:0] words_collected;

    localparam INT_WAIT    = 2'd0;
    localparam INT_RECORD  = 2'd1;
    localparam INT_PROCESS = 2'd2;
    
    reg [1:0] int_state;

    reg [23:0] training_examples [0:14];
    reg word_ready;
    reg [799:0] word_window;
    reg bin_timer_tick;
    reg wake_word_detected;
    reg command_complete;
    integer i;

    reg [7:0] bin_counter;  // 8-bit counter (0-255)
    
    // Additional registers for LED patterns
    reg [7:0] pattern_counter;
    reg [2:0] blink_pattern;
    reg example_ack;
    reg [1:0] progress_phase;
    reg [7:0] progress_timer;
    
    // Generate bin_timer_tick (pulse every 256 clock cycles when counter wraps)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bin_counter <= 8'd0;
            bin_timer_tick <= 1'b0;
        end
        else begin
            bin_counter <= bin_counter + 1;
            bin_timer_tick <= (bin_counter == 8'd255);  // Tick when counter wraps
        end
    end
    
    // Pattern counter for LED sequences
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pattern_counter <= 8'd0;
        blink_pattern <= 3'd0;
        progress_timer <= 8'd0;
        progress_phase <= 2'd0;
    end
    else if (bin_timer_tick) begin
        pattern_counter <= pattern_counter + 1;
        
        // Update blink pattern every 4 ticks
        if (pattern_counter[1:0] == 2'b00)
            blink_pattern <= blink_pattern + 1;
            
        // Progress timer for 2-second indication
        if (word_ready) begin
            progress_timer <= 8'd200;  // ~2 seconds at 100Hz tick
            progress_phase <= 2'd0;
        end
        else if (progress_timer > 0) begin
            progress_timer <= progress_timer - 1;
            
            // Update phase based on timer value (every ~0.5 seconds)
            // This uses the two most significant bits to track 4 phases
            case (progress_timer[7:6])
                2'b11: progress_phase <= 2'd0;
                2'b10: progress_phase <= 2'd1;
                2'b01: progress_phase <= 2'd2;
                2'b00: progress_phase <= 2'd3;
            endcase
        end
    end
end
    
    // Example acknowledgment pulse
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            example_ack <= 1'b0;
        end
        else begin
            if (word_ready) begin
                example_ack <= 1'b1;
            end
            else if (bin_timer_tick && example_ack) begin
                example_ack <= 1'b0;  // Clear after one tick
            end
        end
    end
    
    // Main state machine (unchanged from your code)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sys_state <= SYS_IDLE;
            words_collected <= 4'b0;
            system_ready <= 1'b0;
        end
        else begin
            case (sys_state)
                SYS_IDLE: begin
                    if (button_pressed) begin
                        sys_state <= SYS_TRAINING;
                        words_collected <= 4'b0;
                    end
                end
                
                SYS_TRAINING: begin
                    if (word_ready) begin
                        training_examples[words_collected] <= word_window;
                        words_collected <= words_collected + 1'b1;

                        if (words_collected == 4'd14) begin
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

    // Internal state machine for word collection
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_state <= INT_WAIT;
            word_ready <= 1'b0;
            word_window <= 800'b0;
        end
        else begin
            if (sys_state == SYS_TRAINING) begin
                case (int_state)
                    INT_WAIT: begin
                        if (button_pressed) begin
                            int_state <= INT_RECORD;
                        end
                    end
                    
                    INT_RECORD: begin
                        if (spike_valid) begin
                            // Record logic here
                        end
                        
                        if (!button_pressed) begin
                            int_state <= INT_PROCESS;
                        end
                    end
                    
                    INT_PROCESS: begin
                        // Process logic here
                        word_ready <= 1'b1;
                        int_state <= INT_WAIT;
                    end
                    
                    default: begin
                        int_state <= INT_WAIT;
                    end
                endcase
            end
            else begin
                int_state <= INT_WAIT;
                word_ready <= 1'b0;
            end
        end
    end
    
    // Training progress output
    always @(*) begin
        training_progress = words_collected;
    end

    // LED Control Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led <= 5'b00000;
            wake_word_detected <= 1'b0;
            command_complete <= 1'b0;
        end
        else begin
            // Default assignments
            wake_word_detected <= 1'b0;
            command_complete <= 1'b0;
            
            // LED control based on system state
            case (sys_state)
                SYS_IDLE: begin
                    // IDLE: All LEDs off
                    led <= 5'b00000;
                end
                
                SYS_TRAINING: begin
                    case (int_state)
                        INT_WAIT: begin
                            // WAITING - Show number of collected examples
                            case (words_collected)
                                4'd0:  led <= 5'b00000;                    // 0 examples: all off
                                4'd1:  led <= 5'b00001;                    // 1 example: LED0 on
                                4'd2:  led <= 5'b00011;                    // 2 examples: LEDs 0,1 on
                                4'd3:  led <= 5'b00111;                    // 3 examples: LEDs 0,1,2 on
                                4'd4:  led <= 5'b01111;                    // 4 examples: LEDs 0,1,2,3 on
                                4'd5,4'd6,4'd7,4'd8,4'd9,4'd10,4'd11,4'd12,4'd13,4'd14: 
                                      led <= 5'b11111;                      // 5+ examples: all LEDs on
                                default: led <= 5'b00000;
                            endcase
                            
                            // Override for 2-second progress indication after collection
                            if (progress_timer > 0) begin
                                case (progress_phase)
                                    2'd0: led <= 5'b00001;  // Phase 0: LED0 only
                                    2'd1: led <= 5'b00011;  // Phase 1: LEDs 0,1
                                    2'd2: led <= 5'b00111;  // Phase 2: LEDs 0,1,2
                                    2'd3: led <= 5'b01111;  // Phase 3: LEDs 0,1,2,3
                                endcase
                            end
                        end
                        
                        INT_RECORD: begin
                            // RECORDING: LED0 blinks slowly during recording
                            if (pattern_counter[7])  // Slow blink using MSB
                                led <= 5'b00001;
                            else
                                led <= 5'b00000;
                        end
                        
                        INT_PROCESS: begin
                            // PROCESSING example: Quick blink acknowledgment
                            if (example_ack)
                                led <= 5'b11111;  // All LEDs flash
                            else
                                led <= 5'b00000;
                        end
                        
                        default: begin
                            led <= 5'b00000;
                        end
                    endcase
                end
                
                SYS_TRAIN_PROCESS: begin
                    // PROCESSING all examples: Fast blinking (toggle at pattern_counter[6])
                    if (pattern_counter[6])  // Fast blink
                        led <= 5'b11111;
                    else
                        led <= 5'b00000;
                end
                
                SYS_READY: begin
                    // READY: Progressive pattern cycling
                    case (blink_pattern[2:0])
                        3'd0: led <= 5'b00001;  // LED0 only
                        3'd1: led <= 5'b00011;  // LEDs 0,1
                        3'd2: led <= 5'b00111;  // LEDs 0,1,2
                        3'd3: led <= 5'b01111;  // LEDs 0,1,2,3
                        3'd4: led <= 5'b11111;  // All LEDs
                        default: led <= 5'b11111;
                    endcase
                end
                
                SYS_COMMAND_ACTIVE: begin
                    // COMMAND ACTIVE: Fast blinking all LEDs
                    if (pattern_counter[6])  // Fast blink
                        led <= 5'b11111;
                    else
                        led <= 5'b00000;
                end
                
                default: begin
                    led <= 5'b00000;
                end
            endcase
            
            // Special case: All 15 collected - show processing blink
            if (words_collected == 4'd15 && sys_state == SYS_TRAINING) begin
                if (pattern_counter[6])  // Fast blink
                    led <= 5'b11111;
                else
                    led <= 5'b00000;
            end
        end
    end

endmodule
