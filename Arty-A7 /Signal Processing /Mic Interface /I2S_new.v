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


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clk_div <= 0;
        bclk <= 0;
        lrclk <= 0;
    end 
    else begin
        if (clk_div == 49) begin 
            clk_div <= 0;
            bclk <= ~bclk;

            if (bclk == 1'b1) begin 
                lrclk <= ~lrclk;
            end
        end else begin
            clk_div <= clk_div + 1;
        end
    end
end


always @(posedge bclk or negedge rst_n) begin
    if (!rst_n) begin
        bit_count <= 0;
        shift_reg <= 0;
        sample <= 0;
        sample_valid <= 0;
    end 
    else begin
        sample_valid <= 0;
        
        shift_reg <= {shift_reg[22:0], sd};
        bit_count <= bit_count + 1;
        

        if (bit_count == 17) begin
            sample <= shift_reg[23:8];
            sample_valid <= 1'b1;
        end
        
        if (bit_count == 63) begin
            bit_count <= 0;
        end
    end
end

ila_0 your_instance_name (
	.clk(clk), // input wire clk
	.probe0(rst_n), // input wire [0:0]  probe0  
	.probe1(sd), // input wire [0:0]  probe1 
	.probe2(bclk), // input wire [0:0]  probe2 
	.probe3(lrclk), // input wire [0:0]  probe3 
	.probe4(shift_reg), // input wire [23:0]  probe4 
	.probe5(sample), // input wire [15:0]  probe5 
	.probe6(bit_count), // input wire [5:0]  probe6 
	.probe7(sample_valid) // input wire [0:0]  probe7
);

endmodule
