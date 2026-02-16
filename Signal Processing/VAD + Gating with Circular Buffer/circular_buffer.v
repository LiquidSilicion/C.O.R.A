always @(posedge clk) begin
    if (sample_valid) begin
        circular_buffer[write_ptr] <= audio_sample;
        write_ptr <= (write_ptr == BUFFER_SIZE-1) ? 0 : write_ptr + 1;
    end
end
