module lif_array #(
    parameter NH    = 8,               // neurons - start at 8, scale to 128
    parameter ALPHA = 16'h00E0,        // α = 0.875 in Q8.8
    parameter THETA = 16'h0100         // θ = 1.0   in Q8.8
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          clear_state,
    input  wire [15:0]   lif_acc,      // Q8.8 synaptic current for neuron lif_idx
    input  wire [6:0]    lif_idx,      // neuron index (0 .. NH-1)
    input  wire          lif_wen,      // strobe: write lif_acc into accumulator
    input  wire          lif_capture,  // strobe: trigger fire/reset swee
    output reg  [NH-1:0] lif_spikes,   // registered spike vector; stable until next capture
    output reg           capture_done  // one-cycle pulse: lif_spikes is now valid
);
    reg [15:0] accum [0:NH-1];
    reg [15:0] vm    [0:NH-1];

    localparam [1:0]
        ST_IDLE  = 2'd0,
        ST_SWEEP = 2'd1,
        ST_DONE  = 2'd2;
 
    reg [1:0] cap_state;
    reg [7:0] cap_idx;          // neuron index during sweep (8 bits covers NH=128)
 
    // α · V_old  →  Q8.8 × Q8.8 = Q16.16, keep [23:8]
    wire signed [31:0] alpha_x_vm = $signed({1'b0, ALPHA}) * $signed({1'b0, vm[cap_idx]});
    wire [15:0] v_decayed         = alpha_x_vm[23:8];
 
    // V_new = α·V_old + I_syn  (17-bit to catch overflow; overflow saturates)
    wire [16:0] v_new_full = {1'b0, v_decayed} + {1'b0, accum[cap_idx]};
    wire [15:0] v_new      = v_new_full[16] ? 16'hFFFF : v_new_full[15:0];
 
    // fire decision
    wire fire = (v_new >= THETA);
 
    // ─── spike staging register ──────────────────────────────────────────────
    reg [NH-1:0] spike_next;
 
    integer ci;
 
    // ─── main clocked process ────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            cap_state    <= ST_IDLE;
            cap_idx      <= 0;
            lif_spikes   <= 0;
            capture_done <= 0;
            spike_next   <= 0;
            for (ci = 0; ci < NH; ci = ci+1) begin
                vm   [ci] <= 16'h0000;
                accum[ci] <= 16'h0000;
            end
 
        end else begin
 
            // ── pulse defaults ───────────────────────────────────────────────
            capture_done <= 0;
 
            // ── accumulator write (from mac_engine, one per cycle) ──────────
            // mac_engine guarantees lif_wen is never asserted during the
            // capture sweep, so there is no write-vs-read hazard on accum[].
            if (lif_wen)
                accum[lif_idx] <= lif_acc;
 
            // ── V_m clear (between training runs if needed) ─────────────────
            if (clear_state)
                for (ci = 0; ci < NH; ci = ci+1)
                    vm[ci] <= 16'h0000;
 
            // ── capture FSM ──────────────────────────────────────────────────
            case (cap_state)
 
                // ─────────────────────────────────────────────────────────────
                ST_IDLE: begin
                    if (lif_capture) begin
                        cap_idx    <= 0;
                        spike_next <= 0;
                        cap_state  <= ST_SWEEP;
                    end
                end
 
                // ─────────────────────────────────────────────────────────────
                // One neuron per cycle.
                // v_decayed, v_new, and fire are all combinational from
                // cap_idx, so they are valid the same cycle and can be used
                // directly in the non-blocking assignments below.
                // ─────────────────────────────────────────────────────────────
                ST_SWEEP: begin
                    if (fire) begin
                        vm[cap_idx]         <= 16'h0000;   // hard reset
                        spike_next[cap_idx] <= 1'b1;
                    end else begin
                        vm[cap_idx]         <= v_new;      // integrate
                        spike_next[cap_idx] <= 1'b0;
                    end
 
                    if (cap_idx == NH-1)
                        cap_state <= ST_DONE;
                    else
                        cap_idx <= cap_idx + 8'd1;
                end
                
                ST_DONE: begin
                    lif_spikes   <= spike_next;  // stable until next capture
                    capture_done <= 1'b1;
                    cap_state    <= ST_IDLE;
                end
 
                default: cap_state <= ST_IDLE;
 
            endcase
        end
    end
endmodule
