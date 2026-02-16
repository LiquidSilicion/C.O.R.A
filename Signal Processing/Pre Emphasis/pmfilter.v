module pm_filter (
    input wire clk,                    
    input wire rst,                    
    input wire signed [15:0] x_n,      // Current audio sample
    output reg signed [15:0] y_n       // Output sample 
);
 reg signed [15:0] x_n_1;           // previous sample
    
    wire signed [15:0] alpha;          // pm coefficient (0.92)
    
    wire signed [31:0] mult_result;    // Result of alpha * x[n-1]
    
    wire signed [15:0] mult_scaled;    // Scaled multiplication result back to 16-bit
    
    wire signed [16:0] sub_result;     // Subtraction result (17-bit to handle overflow)
    
    assign alpha = 16'sb0111010111000010;  // 0.92 × 2^15 = 30146
    
  
    assign mult_result = alpha * x_n_1; // Multiply alpha × x[n-1]
    
    assign mult_scaled = mult_result[30:15]; //Scale back to Q0.15 by taking bits [30:15]
     
    assign sub_result = {x_n[15], x_n} - {mult_scaled[15], mult_scaled};//Subtract x[n] - mult_scaled with sign extension to 17 bits


     always @(posedge clk or posedge rst) begin
        if (rst) begin
            x_n_1 <= 16'sd0;
        end else begin
            x_n_1 <= x_n;
        end
    end
    
    always @(*) begin
        if (sub_result > 17'sd32767) begin
            y_n = 16'sd32767;
        end else if (sub_result < -17'sd32768) begin
            y_n = -16'sd32768;
        end else begin
            y_n = sub_result[15:0];
        end
    end

endmodule
