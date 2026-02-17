function automatic [23:0] state_to_string(input [1:0] state);
        case (state)
            IDLE: state_to_string = "IDLE";
            LOAD: state_to_string = "LOAD";
            COMPUTE: state_to_string = "COMPUTE";
            DONE: state_to_string = "DONE";
            default: state_to_string = "UNKNOWN";
        endcase
    endfunction


always @(posedge clk) begin
        if (en) begin
            // Print current state and relevant information for debugging
            $display("Time %t: State = %s, Next State = %s", $time, state_to_string(state), state_to_string(next_state));
            $display("input_counter = %d, output_counter = %d, row_counter = %d", input_counter, output_counter, row_counter);
            
            if (state == COMPUTE) begin
                $display("Convolution Result: conv_temp = %h", conv_temp);
                for (i = 0; i < k*k; i = i + 1) begin
                    $display("window_buffer[%d] = %h, weight[%d] = %h, product = %h", 
                             i, window_buffer[i], i, weight[i*N +: N], 
                             ($signed(window_buffer[i]) * $signed(weight[i*N +: N])) >>> Q);
                end
            end
            
            if (valid_out) begin
                $display("Valid Output: conv_out = %h", conv_out);
            end
            
            if (done) begin
                $display("Convolution operation completed");
            end
        end
    end
