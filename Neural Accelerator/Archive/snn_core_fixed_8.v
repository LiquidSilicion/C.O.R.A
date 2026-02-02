module snn_core_fixed8(
    input wire clk,
    input wire reset_n,
    input wire [15:0] input_spikes,
    input wire spike_valid,
    output reg [127:0] hidden_spikes, // 128 neuron spikes
    output reg [9:0] command_output,  // 10 command probabilities
    output reg output_valid

    parameter [7:0] W_IN_SIMPLE [0:15][0:7] = '{
    // Each input connects to all 8 neurons with weight 1
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1},
    '{8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1}
};

// Output: Each neuron votes for a different command
parameter [9:0] W_OUT_SIMPLE [0:7] = '{
    10'b1000_0000_00,  // Neuron 0 → Command 0
    10'b0100_0000_00,  // Neuron 1 → Command 1  
    10'b0010_0000_00,  // Neuron 2 → Command 2
    10'b0001_0000_00,  // Neuron 3 → Command 3
    10'b0000_1000_00,  // Neuron 4 → Command 4
    10'b0000_0100_00,  // Neuron 5 → Command 5
    10'b0000_0010_00,  // Neuron 6 → Command 6
    10'b0000_0001_00   // Neuron 7 → Command 7
};
    endmodule
);
