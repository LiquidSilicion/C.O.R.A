module interface(
    input clk,
    input rst_n,        
    input sd,
    output reg bclk,
    output reg lrclk,
    output reg [15:0] sample,
    output reg sample_valid
);

reg [6:0] clk_div = 0;
reg [5:0] bit_count = 0;
reg [23:0] shift_reg = 0;
wire bclk_rising, bclk_falling;

// Clock divider for BCLK
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clk_div <= 0;
        bclk <= 0;
    end else begin
        if (clk_div == 49) begin 
            clk_div <= 0;
            bclk <= ~bclk;
        end else begin
            clk_div <= clk_div + 1;
        end
    end
end

// Detect BCLK edges (using master clock)
assign bclk_rising = (clk_div == 49 && bclk == 0);
assign bclk_falling = (clk_div == 49 && bclk == 1);

// Main I2S receiver (using master clock)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_count <= 0;
        lrclk <= 0;
        shift_reg <= 0;
        sample <= 0;
        sample_valid <= 0;
    end else begin
        sample_valid <= 0;
        
        if (bclk_rising) begin
            // Sample data on BCLK rising edge
            shift_reg <= {shift_reg[22:0], sd};
            bit_count <= bit_count + 1;
            
            // Capture sample at correct bit position
            if (bit_count == 16 && lrclk == 0) begin  // For left channel
                sample <= shift_reg[23:8];  // 16-bit data from 24-bit frame
                sample_valid <= 1'b1;
            end
        end
        
        if (bclk_falling) begin
            // Toggle LRCLK at frame boundaries
            if (bit_count == 63) begin
                bit_count <= 0;
                lrclk <= ~lrclk;
            end
        end
    end
end

// ILA for debugging
ila_0 your_instance_name (
    .clk(clk),
    .probe0(rst_n),
    .probe1(sd),
    .probe2(bclk),
    .probe3(lrclk),
    .probe4(shift_reg),
    .probe5(sample),
    .probe6(bit_count),
    .probe7(sample_valid)
);

endmodule
