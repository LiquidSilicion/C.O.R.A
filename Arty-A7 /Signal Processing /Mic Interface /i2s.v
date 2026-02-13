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

// ILA debug signals - add markers to the signals you want to monitor
(* mark_debug = "true" *) wire        debug_bclk = bclk;
(* mark_debug = "true" *) wire        debug_lrclk = lrclk;
(* mark_debug = "true" *) wire        debug_sd = sd;
(* mark_debug = "true" *) wire [15:0] debug_sample = sample;
(* mark_debug = "true" *) wire        debug_sample_valid = sample_valid;
(* mark_debug = "true" *) wire [5:0]  debug_bit_count = bit_count;
(* mark_debug = "true" *) wire [23:0] debug_shift_reg = shift_reg;

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
