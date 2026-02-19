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
    reg lrclk_sync, lrclk_prev;
    reg sd_sync;
    reg [15:0] shift_reg;
    reg [4:0] bit_count;
    reg [15:0] left_chan, right_chan;
    
    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_sync <= 0;
            bclk_prev <= 0;
            lrclk_sync <= 0;
            lrclk_prev <= 0;
            sd_sync <= 0;
            shift_reg <= 0;
            bit_count <= 0;
            audio_sample <= 0;
            sample_valid <= 0;
        end else begin
            bclk_sync <= bclk;
            bclk_prev <= bclk_sync;
            lrclk_sync <= lrclk;
            lrclk_prev <= lrclk_sync;
            sd_sync <= sd;
            
            sample_valid <= 0;
            
            if (lrclk_sync != lrclk_prev) begin
                bit_count <= 0;
            end
            
            if (bclk_sync && !bclk_prev) begin
                shift_reg <= {shift_reg[14:0], sd_sync};
                bit_count <= bit_count + 1;
                
                if (bit_count == 15) begin
                    audio_sample <= {shift_reg[14:0], sd_sync};
                    sample_valid <= 1'b1;
                    bit_count <= 0;
                end
            end
        end
    end

endmodule
