module i2s_protocol(
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

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clk_div <= 0;
        bclk <= 0;
    end 
    else begin
        if (clk_div == 49) begin 
            clk_div <= 0;
            bclk <= ~bclk;
        end else begin
            clk_div <= clk_div + 1;
        end
    end
end

wire bclk_rising = (clk_div == 49 && bclk == 0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_count <= 0;
        lrclk <= 1;
        shift_reg <= 0;
        sample <= 0;
        sample_valid <= 0;
    end else begin
        sample_valid <= 0;
        
        if (bclk_rising) begin
            shift_reg <= {shift_reg[22:0], sd};
            bit_count <= bit_count + 1;
            
            if (bit_count == 17 && lrclk == 0) begin
                sample <= shift_reg[23:8];
                sample_valid <= 1'b1;
            end
            
            if (bit_count == 63) begin
                bit_count <= 0;
                lrclk <= ~lrclk;
            end
        end
    end
end

endmodule
