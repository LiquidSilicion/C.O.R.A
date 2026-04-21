// ============================================================
//  aer_top.v
//  AER Encoder — standalone top module
//
//  Input:  spike[15:0]  from lif_top via spike_bus wire
//  Output: data[23:0]   AER packet to SNN
//
//  Thin wrapper around aer_encoder.v
//  Exists so LIF and AER can be separate Vivado modules
// ============================================================

module aer_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_en,

    // spike bus from lif_top
    input  wire [15:0] spike,

    // AER output to SNN
    output wire [23:0] data,
    output wire        aer_valid,
    input  wire        aer_ready
);

    aer_encoder u_aer (
        .clk      (clk),
        .rst_n    (rst_n),
        .sample_en(sample_en),
        .spike    (spike),
        .data     (data),
        .aer_valid(aer_valid),
        .aer_ready(aer_ready)
    );

endmodule
