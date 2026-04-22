module lowpass_filter(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [15:0] x_in,       // unsigned input from half wave rectifier
    output reg  [15:0] y_out,       // 16-bit envelope output A(t)
    output reg         valid_out
);

    // =============================================
    // 2nd Order Butterworth Lowpass Biquad
    // Cutoff: 300Hz, Fs: 16kHz, Fixed point: Q2.14
    //
    // K = tan(pi*300/16000) = 0.05891
    // norm = 1/(1 + sqrt(2)*K + K^2)
    //
    // RAW coefficients (before gain normalisation):
    //   b0 = K^2 * norm         = 0.003202
    //   b1 = 2*K^2 * norm       = 0.006404
    //   b2 = K^2 * norm         = 0.003202
    //   a1 = 2*(K^2-1)*norm     = -1.8337   (stored as +30044, subtracted in eq)
    //   a2 = (1-sqrt(2)*K+K^2)*norm = 0.8465
    //
    // DC gain of raw filter = (b0+b1+b2)/(1+a1_coeff-a2)
    //   with a1_coeff = -1.8337:
    //   = (3*0.003202)/(1 + (-1.8337) - 0.8465) ... wait
    //   DC gain = (b0+b1+b2) / (1 - (-a1_stored_sign) + a2)
    //           = 209/16384 / (16384+30044-13870)/16384
    //           = 209 / 32558 = 0.00641
    //
    // GAIN-NORMALISED B coefficients (multiply by 16384/209 = 78.4):
    //   B0 = 52  * 78.4 = 4076  (Q2.14)
    //   B1 = 105 * 78.4 = 8232  → use 8152 to avoid rounding overshoot
    //   B2 = 52  * 78.4 = 4076  (Q2.14)
    //
    // A coefficients unchanged:
    //   A1 = 30044  (positive magnitude, subtracted in biquad eq)
    //   A2 = 13870  (positive, subtracted in biquad eq)
    // =============================================

    localparam signed [15:0] B0 =  16'sd4076;
    localparam signed [15:0] B1 =  16'sd8152;
    localparam signed [15:0] B2 =  16'sd4076;
    localparam signed [15:0] A1 =  16'sd30044;  // positive magnitude, subtracted
    localparam signed [15:0] A2 =  16'sd13870;  // positive, subtracted

    // Filter state registers
    reg signed [15:0] x_n1, x_n2;
    reg signed [15:0] y_n1, y_n2;

    // 32-bit accumulator - biquad equation:
    // y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
    // (A1 is positive magnitude so subtract gives correct negative feedback)
    wire signed [31:0] acc;
    assign acc = (B0 * $signed(x_in))
               + (B1 * x_n1)
               + (B2 * x_n2)
               - (A1 * y_n1)
               - (A2 * y_n2);

    // Scale back from Q2.14: divide by 2^14, take bits [29:14]
    // Saturation: check bits [31:30] for overflow
    //   00 or 11 = normal range
    //   01       = positive overflow → clamp to max
    //   10       = negative overflow → clamp to min
    wire signed [15:0] y_next;
    assign y_next = (acc[31] == 1'b0 && acc[30:29] != 2'b00) ? 16'sd32767  :
                    (acc[31] == 1'b1 && acc[30:29] != 2'b11) ? -16'sd32768 :
                    acc[29:14];

    always @(posedge clk) begin
        if (!rst_n) begin
            x_n1      <= 16'sd0;
            x_n2      <= 16'sd0;
            y_n1      <= 16'sd0;
            y_n2      <= 16'sd0;
            y_out     <= 16'd0;
            valid_out <= 1'b0;
        end
        else if (valid_in) begin
            x_n2      <= x_n1;
            x_n1      <= $signed(x_in);
            y_n2      <= y_n1;
            y_n1      <= y_next;
            y_out     <= y_next;
            valid_out <= 1'b1;
        end
        else begin
            valid_out <= 1'b0;
        end
    end
endmodule
