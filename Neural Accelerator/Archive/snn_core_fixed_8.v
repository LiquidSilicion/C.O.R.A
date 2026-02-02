module snn_core_fixed8(
    input wire clk,
    input wire reset_n,
    input wire [15:0] input_spikes,
    input wire spike_valid,
    output reg [127:0] hidden_spikes, // 128 neuron spikes
    output reg [9:0] command_output,  // 10 command probabilities
    output reg output_valid
);
