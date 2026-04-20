`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: pipeline_sequencer
// Purpose: Controls the MAC start signal.
// Waits for both window_ready AND spike_readback done before asserting mac_start.
// Can be used standalone or inlined into snn_accelerator_top.
//
// State machine:
//   IDLE  → (win_ready)  → READBACK   (wait for spike readback)
//   READBACK → (rb_done) → ARM        (1-cycle setup)
//   ARM   →               RUN         (mac_start asserted here for 1 cycle)
//   RUN   → (mac_done)  → WAIT_VOTER  (wait for output layer)
//   WAIT_VOTER → (result_valid) → IDLE
//////////////////////////////////////////////////////////////////////////////////

module pipeline_sequencer (
    input  wire clk,
    input  wire rst_n,
    input  wire win_ready,      // From window accumulator
    input  wire rb_done,        // From spike_readback
    input  wire mac_done,       // From MAC engine
    input  wire result_valid,   // From output layer
    output reg  mac_start,      // To MAC engine (1-cycle pulse)
    output wire busy            // High between win_ready and result_valid
);

    localparam [2:0]
        S_IDLE       = 3'd0,
        S_READBACK   = 3'd1,
        S_ARM        = 3'd2,
        S_RUN        = 3'd3,
        S_WAIT_VOTER = 3'd4;

    reg [2:0] state;

    assign busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            mac_start <= 1'b0;
        end else begin
            mac_start <= 1'b0;
            case (state)
                S_IDLE:       if (win_ready)    state <= S_READBACK;
                S_READBACK:   if (rb_done)      state <= S_ARM;
                S_ARM: begin
                    mac_start <= 1'b1;
                    state     <= S_RUN;
                end
                S_RUN:        if (mac_done)     state <= S_WAIT_VOTER;
                S_WAIT_VOTER: if (result_valid) state <= S_IDLE;
                default:      state <= S_IDLE;
            endcase
        end
    end

endmodule
