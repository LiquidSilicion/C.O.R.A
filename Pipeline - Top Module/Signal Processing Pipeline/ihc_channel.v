module ihc_channel(    
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire signed [15:0] x_in,       // 16-bit signed from BPF
    output wire [15:0] y_out,       // 16-bit envelope A(t) to LIF neuron
    output wire        valid_out

    );
        // =============================================
    // IHC Single Channel Pipeline - Correct Order
    //
    // Stage 1: Nonlinear Compression  (NL)
    // Stage 2: Adaptation Filter      (AF)
    // Stage 3: Half Wave Rectifier    (HWR)
    // Stage 4: Lowpass Filter         (LP)
    // =============================================
 
    // Stage 1 to Stage 2
    wire [15:0] nl_to_af;
    wire        nl_valid;
 
    // Stage 2 to Stage 3
    wire signed [15:0] af_to_hwr;
    wire               af_valid;
 
    // Stage 3 to Stage 4
    wire [15:0] hwr_to_lp;
    wire        hwr_valid;
 
    // Stage 1: Nonlinear Compression
    nonlinear_compression u_nl (
        .clk       (clk),
        .rst_n       (rst_n),
        .valid_in  (valid_in),
        .x_in      (x_in),
        .y_out     (nl_to_af),
        .valid_out (nl_valid)
    );
 
    // Stage 2: Adaptation Filter
    adaptation_filter u_af (
        .clk       (clk),
        .rst_n      (rst_n),
        .valid_in  (nl_valid),
        .x_in      (nl_to_af),
        .y_out     (af_to_hwr),
        .valid_out (af_valid)
    );
 
    // Stage 3: Half Wave Rectifier
    half_wave_rectifier u_hwr (
        .clk       (clk),
        .rst_n       (rst_n),
        .valid_in  (af_valid),
        .x_in      (af_to_hwr),
        .y_out     (hwr_to_lp),
        .valid_out (hwr_valid)
    );
 
    // Stage 4: Lowpass Envelope Filter
    lowpass_filter u_lp (
        .clk       (clk),
        .rst_n       (rst_n),
        .valid_in  (hwr_valid),
        .x_in      (hwr_to_lp),
        .y_out     (y_out),
        .valid_out (valid_out)
    );
endmodule
