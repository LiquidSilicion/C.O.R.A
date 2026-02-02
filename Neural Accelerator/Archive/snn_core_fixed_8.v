module snn_core_fixed8(
    input wire clk,
    input wire reset_n,
    input wire [15:0] input_spikes,
    input wire spike_valid,
    output reg [127:0] hidden_spikes, // 128 neuron spikes
    output reg [9:0] command_output,  // 10 command probabilities
    output reg output_valid

    parameter [7:0] w_in_test [0:15][0:7] = '{
    // Input 0: Mostly connects to neurons that detect "A" sounds
    '{8'd0, 8'd0, 8'd0, 8'd10, 8'd1, 8'd1, 8'd1, 8'd1},
    // Input 1: Strong to "A" detector (neuron 3), weak to others
    '{8'd0, 8'd0, 8'd0, 8'd12, 8'd1, 8'd2, 8'd1, 8'd0},
    // Input 2: "O" sound frequency → Neuron 1
    '{8'd0, 8'd15, 8'd0, 8'd0, 8'd2, 8'd1, 8'd1, 8'd1},
    // Input 3: "C" sound frequency → Neuron 0  
    '{8'd20, 8'd0, 8'd1, 8'd0, 8'd1, 8'd1, 8'd2, 8'd1},
    // Input 4: "R" sound frequency → Neuron 2
    '{8'd1, 8'd0, 8'd18, 8'd0, 8'd2, 8'd1, 8'd1, 8'd1},
    // Input 5: "A" sound frequency → Neuron 3
    '{8'd0, 8'd0, 8'd0, 8'd15, 8'd1, 8'd1, 8'd2, 8'd1},
    // Input 6: "O" sound frequency → Neuron 1
    '{8'd0, 8'd14, 8'd0, 8'd0, 8'd1, 8'd2, 8'd1, 8'd1},
    // Input 7: "C" sound frequency → Neuron 0
    '{8'd18, 8'd0, 8'd1, 8'd0, 8'd1, 8'd1, 8'd1, 8'd2},
    // Input 8: "R" sound frequency → Neuron 2
    '{8'd1, 8'd0, 8'd16, 8'd0, 8'd1, 8'd1, 8'd2, 8'd1},
    // Input 9: "A" sound frequency → Neuron 3
    '{8'd0, 8'd0, 8'd0, 8'd14, 8'd2, 8'd1, 8'd1, 8'd1},
    // Input 10: "O" sound frequency → Neuron 1
    '{8'd0, 8'd13, 8'd0, 8'd0, 8'd1, 8'd1, 8'd1, 8'd2},
    // Input 11: "C" sound frequency → Neuron 0
    '{8'd15, 8'd0, 8'd2, 8'd0, 8'd1, 8'd2, 8'd1, 8'd1},
    // Input 12: "R" sound frequency → Neuron 2
    '{8'd1, 8'd0, 8'd17, 8'd0, 8'd2, 8'd1, 8'd1, 8'd1},
    // Input 13-15: Other frequencies, weaker connections
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd5, 8'd5, 8'd5, 8'd5},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd5, 8'd4, 8'd6, 8'd5},
    '{8'd2, 8'd1, 8'd1, 8'd1, 8'd4, 8'd5, 8'd5, 8'd6}
};
parameter [9:0] W_OUT_SIMPLE [0:7] = '{
    10'b1000000000,
    10'b0100000000,
    10'b0010000000,
    10'b0001000000,
    10'b0000100000,
    10'b0000010000,
    10'b0000001000,
    10'b0000000100,
    10'b0000000010,
    10'b0000000001
};
    endmodule
);
