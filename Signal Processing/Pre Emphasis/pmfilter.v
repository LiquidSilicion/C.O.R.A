// Pre-Emphasis Filter Module
// Implements: y[n] = x[n] - 0.92 × x[n-1]
// Author: [Your Name]
// Date: [Date]

module pm_filter (
    input wire clk,                    // Clock signal
    input wire rst,                    // Reset signal (active high)
    input wire signed [15:0] x_n,      // Current audio sample x[n]
    output reg signed [15:0] y_n       // Output sample y[n]
);

    // ===================================
    // Internal Signal Declarations
    // ===================================
    reg signed [15:0] x_n_1;           // Delayed sample x[n-1]
    
    wire signed [15:0] alpha;          // Pre-emphasis coefficient (0.92)
    
    wire signed [31:0] mult_result;    // Result of alpha * x[n-1] (32-bit)
    
    wire signed [15:0] mult_scaled;    // Scaled multiplication result (16-bit)
    
    wire signed [16:0] sub_result;     // Subtraction result (17-bit for overflow detection)
    
    // ===================================
    // Combinational Logic
    // ===================================
    
    // Assign alpha constant (0.92 in Q0.15 fixed-point format)
    // 0.92 × 2^15 = 30146
    assign alpha = 16'sd30146;
    
    // Step 1: Multiply alpha × x[n-1] (results in 32-bit Q0.30 format)
    assign mult_result = alpha * x_n_1;
    
    // Step 2: Scale back to Q0.15 by extracting bits [30:15]
    // This is equivalent to dividing by 2^15
    assign mult_scaled = mult_result[30:15];
    
    // Step 3: Subtract x[n] - mult_scaled with sign extension to 17 bits
    // Sign extension prevents overflow during subtraction
    assign sub_result = {x_n[15], x_n} - {mult_scaled[15], mult_scaled};
    
    // ===================================
    // Sequential Logic - Delay Register
    // ===================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset: clear the delay register
            x_n_1 <= 16'sd0;
        end else begin
            // Normal operation: store current sample for next cycle
            // This creates the one-sample delay (x[n-1])
            x_n_1 <= x_n;
        end
    end
    
    // ===================================
    // Combinational Logic - Saturation
    // ===================================
    always @(*) begin
        if (sub_result > 17'sd32767) begin
            // Positive overflow: saturate to max positive value
            y_n = 16'sd32767;
        end else if (sub_result < -17'sd32768) begin
            // Negative overflow: saturate to max negative value
            y_n = -16'sd32768;
        end else begin
            // No overflow: take lower 16 bits
            y_n = sub_result[15:0];
        end
    end

endmodule
