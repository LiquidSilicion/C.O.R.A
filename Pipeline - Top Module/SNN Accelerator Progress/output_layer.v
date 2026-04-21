module output_layer #(
    parameter NO = 10,    // number of output classes
    parameter NH = 128    // number of hidden neurons (must match mac_engine)
)(
    input  wire               clk,
    input  wire               rst_n,
 
    // ── from mac_engine (Stage 11/12) ────────────────────────────────────────
    input  wire [NO*32-1:0]   score_out,    // Q16.16 per-class scores
    input  wire               score_valid,  // one-cycle pulse
 
    // ── to Mode FSM / Display Controller (Stage 15/16) ────────────────────
    output reg  [3:0]         cmd_id,       // argmax class index
    output reg  [15:0]        confidence,   // Q8.8 winning combined score
    output reg                result_valid, // one-cycle pulse
 
    // ── debug ─────────────────────────────────────────────────────────────
    output wire [NO*32-1:0]   combined_scores  // A+B before argmax
);
 
    // ─────────────────────────────────────────────────────────────────────────
    // Score banks  (Stage 14 - Overlap Voter)
    // bank_a = window N-1,  bank_b = window N  (most recent)
    // On each new score_valid: a ← b, b ← new scores.
    // ─────────────────────────────────────────────────────────────────────────
    reg signed [31:0] bank_a [0:NO-1];   // window N-1 scores
    reg signed [31:0] bank_b [0:NO-1];   // window N   scores
 
    // combined[c] = bank_a[c] + bank_b[c]
    wire signed [32:0] combined [0:NO-1];  // 33-bit to hold sum without overflow
    genvar g;
    generate
        for (g = 0; g < NO; g = g+1) begin : gen_combine
            assign combined[g]                   = bank_a[g] + bank_b[g];
            assign combined_scores[g*32 +: 32]   = combined[g][32:1]; // >>1 to fit 32b
        end
    endgenerate
 
    // ─────────────────────────────────────────────────────────────────────────
    // Argmax FSM
    // Iterates over all NO classes sequentially (one per cycle).
    // Keeps a running max and the index of that max.
    // ─────────────────────────────────────────────────────────────────────────
    localparam [1:0]
        AX_IDLE  = 2'd0,
        AX_SCAN  = 2'd1,
        AX_DONE  = 2'd2;
 
    reg [1:0]         ax_state;
    reg [3:0]         ax_idx;           // current class being compared
    reg signed [32:0] ax_max;           // running maximum combined score
    reg [3:0]         ax_best;          // index of running maximum
 
    // ─────────────────────────────────────────────────────────────────────────
    // Latch new scores and shift banks on score_valid
    // ─────────────────────────────────────────────────────────────────────────
    integer i;
 
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < NO; i = i+1) begin
                bank_a[i] <= 32'sd0;
                bank_b[i] <= 32'sd0;
            end
            cmd_id       <= 4'd0;
            confidence   <= 16'h0000;
            result_valid <= 1'b0;
            ax_state     <= AX_IDLE;
            ax_idx       <= 4'd0;
            ax_max       <= 33'sd0;
            ax_best      <= 4'd0;
 
        end else begin
 
            result_valid <= 1'b0;   // default
 
            // ── Stage 13: latch scores + Stage 14: shift banks ────────────
            if (score_valid) begin
                for (i = 0; i < NO; i = i+1) begin
                    bank_a[i] <= bank_b[i];                        // shift: b→a
                    bank_b[i] <= $signed(score_out[i*32 +: 32]);   // latch new
                end
            end
 
            // ── Stage 14: argmax FSM ──────────────────────────────────────
            case (ax_state)
 
                AX_IDLE: begin
                    // Start argmax one cycle after score_valid so bank_b has
                    // settled (non-blocking assignment above takes effect at
                    // end of this time step; combined[] is combinational so
                    // it reflects new values next cycle).
                    if (score_valid) begin
                        ax_idx   <= 4'd0;
                        ax_max   <= 33'sh1_FFFF_FFFF; // most-negative 33-bit signed
                        ax_best  <= 4'd0;
                        ax_state <= AX_SCAN;
                    end
                end
 
                AX_SCAN: begin
                    // Compare current class against running max
                    if (combined[ax_idx] > ax_max) begin
                        ax_max  <= combined[ax_idx];
                        ax_best <= ax_idx;
                    end
                    if (ax_idx == NO-1)
                        ax_state <= AX_DONE;
                    else
                        ax_idx <= ax_idx + 4'd1;
                end
 
                AX_DONE: begin
                    cmd_id       <= ax_best;
                    // confidence: winning combined score, Q16.16→Q8.8 = bits[23:8]
                    // ax_max is the 33-bit sum; shift right by 1 to get 32-bit,
                    // then take [23:8] for Q8.8.
                    confidence   <= ax_max[24:9];
                    result_valid <= 1'b1;
                    ax_state     <= AX_IDLE;
                end
 
                default: ax_state <= AX_IDLE;
 
            endcase
        end
    end
 
endmodule
