// ============================================================
//  lif_aer_top.v
//  16 LIF Neurons + AER Encoder
// ============================================================

module lif_aer_top #(
    parameter LEAK_FACTOR = 15'd31130,
    parameter THRESHOLD   = 32'd16000,
    parameter REFRAC      = 4'd8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_en,
    input  wire [15:0] ihc_ch1,  input  wire [15:0] ihc_ch2,
    input  wire [15:0] ihc_ch3,  input  wire [15:0] ihc_ch4,
    input  wire [15:0] ihc_ch5,  input  wire [15:0] ihc_ch6,
    input  wire [15:0] ihc_ch7,  input  wire [15:0] ihc_ch8,
    input  wire [15:0] ihc_ch9,  input  wire [15:0] ihc_ch10,
    input  wire [15:0] ihc_ch11, input  wire [15:0] ihc_ch12,
    input  wire [15:0] ihc_ch13, input  wire [15:0] ihc_ch14,
    input  wire [15:0] ihc_ch15, input  wire [15:0] ihc_ch16,
    output wire [23:0] data,
    output wire        aer_valid,
    input  wire        aer_ready,
    output wire [15:0] spike_bus
);

    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif1  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch1), .spike(spike_bus[0]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif2  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch2), .spike(spike_bus[1]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif3  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch3), .spike(spike_bus[2]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif4  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch4), .spike(spike_bus[3]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif5  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch5), .spike(spike_bus[4]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif6  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch6), .spike(spike_bus[5]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif7  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch7), .spike(spike_bus[6]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif8  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch8), .spike(spike_bus[7]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif9  (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch9), .spike(spike_bus[8]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif10 (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch10),.spike(spike_bus[9]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif11 (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch11),.spike(spike_bus[10]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif12 (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch12),.spike(spike_bus[11]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif13 (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch13),.spike(spike_bus[12]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif14 (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch14),.spike(spike_bus[13]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif15 (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch15),.spike(spike_bus[14]));
    lif_neuron #(.LEAK_FACTOR(LEAK_FACTOR),.THRESHOLD(THRESHOLD),.REFRAC(REFRAC))
    u_lif16 (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.ihc_in(ihc_ch16),.spike(spike_bus[15]));

    aer_encoder u_aer (
        .clk       (clk),
        .rst_n     (rst_n),
        .sample_en (sample_en),
        .spike     (spike_bus),
        .data      (data),
        .aer_valid (aer_valid),
        .aer_ready (aer_ready)
    );

endmodule
