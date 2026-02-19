module i2s(
    input wire mclk,
    input wire rst_n,
    input wire bclk,
    input wire lrclk,
    input wire sd,
    
    output reg [15:0] audio_sample,
    output reg sample_valid
);

    reg bclk_sync, bclk_prev;
    reg lrclk_sync;
    reg sd_sync;
    reg [31:0] shift_reg;
    reg [4:0] bit_count;
    reg [15:0] left_chan, right_chan;
    
    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_sync <= 0;
            bclk_prev <= 0;
            lrclk_sync <= 0;
            sd_sync <= 0;
            shift_reg <= 0;
            bit_count <= 0;
            audio_sample <= 0;
            sample_valid <= 0;
        end else begin
            bclk_sync <= bclk;
            bclk_prev <= bclk_sync;
            lrclk_sync <= lrclk;
            sd_sync <= sd;
            
            sample_valid <= 0;
            
            if (bclk_sync && !bclk_prev) begin  // Rising edge
                shift_reg <= {shift_reg[30:0], sd_sync};
                bit_count <= bit_count + 1;
                
                // After 16 bits, we have a complete sample
                if (bit_count == 16) begin
                    // Use left channel (or average both channels)
                    audio_sample <= shift_reg[15:0];
                    sample_valid <= 1'b1;
                    bit_count <= 0;
                end
            end
        end
    end

endmodule
