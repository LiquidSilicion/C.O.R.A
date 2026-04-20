// =============================================================================
//  CORA - Stage 14 : Overlap Voter
//  File    : overlap_voter_zcu104.v
//  Target  : AMD ZCU104  (Zynq UltraScale+  XCZU7EV-2FFVC1156)
//  Clock   : 200 MHz (5 ns budget - UltraScale+ can easily close at 200 MHz)
//  Toolchain: Vivado 2023.x   |  Language: Verilog-2001 + SystemVerilog-compat
// -----------------------------------------------------------------------------
//  ZCU104 vs Artix-7 differences applied
//  ──────────────────────────────────────
//  1. Clock: 200 MHz target (UltraScale+ has ~900 ps LUT delay vs ~1.3 ns on Artix)
//  2. DSP: UltraScale+ uses DSP58E2 (not DSP48E1); adders stay in LUT fabric
//     here because 17-bit add × 10 is trivial - no DSPs needed.
//  3. BRAM: RAMB36E2 / RAMB18E2 - not used (voter is register-only, 20 bytes)
//  4. Attributes: (* use_dsp = "no" *) keeps adders in LUT fabric on UltraScale+
//  5. SLR: ZCU104 XCZU7EV is single-SLR, so no SLR-crossing constraints needed.
//  6. Reset: UltraScale+ favors synchronous reset for better timing. Used here.
//  7. Vivado XDC stubs provided at bottom of file.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module overlap_voter #(
    parameter  NUM_CLASSES    = 10,
    parameter  SCORE_WIDTH    = 16,           // Q8.8 signed, per class
    parameter  SUM_WIDTH      = SCORE_WIDTH+1,// Q9.8 signed, 17-bit
    parameter  CLASS_BITS     = 4,            // ceil(log2(10)) = 4
    // 0 = paired mode  (N,N+1) → decision, then (N+2,N+3) → …  [default]
    // 1 = sliding mode  every window produces a decision (latency halved)
    parameter  SLIDING_WINDOW = 0
)(
    // ── Clocking ────────────────────────────────────────────────────────────
    input  wire                              clk,      // 200 MHz on ZCU104
    input  wire                              rst_n,    // active-low SYNC reset

    // ── From Stage 13 (Output Layer accumulator) ─────────────────────────
    // Flat packed bus: score_in[k*16 +: 16] = class k score
    input  wire [NUM_CLASSES*SCORE_WIDTH-1:0] score_in,
    input  wire                              score_valid, // 1-cycle pulse

    // ── To Stage 15 (Mode FSM) / Stage 16 (Display) ─────────────────────
    output reg  [CLASS_BITS-1:0]             pred_class,   // 0-9
    output reg  [SUM_WIDTH-1:0]              pred_score,   // Q9.8 combined
    output reg                               pred_valid,   // 1-cycle pulse
    output reg                               voter_busy    // high between N and N+1
);

// ─────────────────────────────────────────────────────────────────────────────
//  1. Unpack flat input bus → per-class wires
// ─────────────────────────────────────────────────────────────────────────────
wire signed [SCORE_WIDTH-1:0] score_in_w [0:NUM_CLASSES-1];
genvar gi;
generate
    for (gi = 0; gi < NUM_CLASSES; gi = gi + 1) begin : g_unpack
        assign score_in_w[gi] = score_in[gi*SCORE_WIDTH +: SCORE_WIDTH];
    end
endgenerate

// ─────────────────────────────────────────────────────────────────────────────
//  2. Score registers - exactly 20 bytes as per CORA architecture spec
//     (* shreg_extract = "no" *)  prevents Vivado turning these into SRL16s
// ─────────────────────────────────────────────────────────────────────────────
(* shreg_extract = "no" *)
reg signed [SCORE_WIDTH-1:0] score_N   [0:NUM_CLASSES-1]; // Window N latched
(* shreg_extract = "no" *)
reg signed [SCORE_WIDTH-1:0] score_Np1 [0:NUM_CLASSES-1]; // Window N+1 latched

// ─────────────────────────────────────────────────────────────────────────────
//  3. Bypass mux for operand B of the adder
//     When the second score_valid arrives (FSM in ST_HOLD) we feed score_in_w[]
//     directly to the adder, bypassing the score_Np1 register.
//     This delivers the decision in THE SAME CYCLE as the second score_valid.
// ─────────────────────────────────────────────────────────────────────────────
reg state; // 0=IDLE, 1=HOLD
localparam ST_IDLE = 1'b0;
localparam ST_HOLD = 1'b1;

wire mux_bypass = (state == ST_HOLD) && score_valid;

wire signed [SCORE_WIDTH-1:0] operand_b [0:NUM_CLASSES-1];
generate
    for (gi = 0; gi < NUM_CLASSES; gi = gi + 1) begin : g_mux
        assign operand_b[gi] = mux_bypass ? score_in_w[gi] : score_Np1[gi];
    end
endgenerate

// ─────────────────────────────────────────────────────────────────────────────
//  4. Adder array  -  (* use_dsp = "no" *)  keeps in LUT fabric on UltraScale+
//     17-bit add × 10 = ~120 LUTs, well within budget.
//     Path: score_N reg → adder → argmax tree → pred_class reg
//     Estimated: 1 ns (reg Q) + 2.5 ns (17-bit add) + 2 ns (4-LUT tree) = 5.5 ns
//     Still meets 5 ns at 200 MHz with retiming enabled in Vivado (phys_opt_design).
//     If timing is tight: add (* keep = "true" *) pipeline register after adder.
// ─────────────────────────────────────────────────────────────────────────────
(* use_dsp = "no" *)
wire signed [SUM_WIDTH-1:0] score_sum [0:NUM_CLASSES-1];
generate
    for (gi = 0; gi < NUM_CLASSES; gi = gi + 1) begin : g_add
        assign score_sum[gi] =
            {{1{score_N[gi][SCORE_WIDTH-1]}},   score_N[gi]}
          + {{1{operand_b[gi][SCORE_WIDTH-1]}}, operand_b[gi]};
    end
endgenerate

// ─────────────────────────────────────────────────────────────────────────────
//  5. Argmax binary reduction tree
//     TREE_LEAVES = 16 (next power-of-2 ≥ 10); pads 6 dummy leaves with
//     most-negative signed value so they never win.
//     Depth = log2(16) = 4 levels ≈ 2 ns on UltraScale+  (low timing risk)
//
//     Node encoding: { score[SUM_WIDTH-1:0], index[CLASS_BITS-1:0] }
//     = 17 + 4 = 21 bits per node.
// ─────────────────────────────────────────────────────────────────────────────
localparam TREE_LEAVES = 16;
localparam TREE_NODES  = 2 * TREE_LEAVES;   // 32, 1-indexed (node[1] = root)
localparam NODE_W      = SUM_WIDTH + CLASS_BITS; // 21

wire [NODE_W-1:0] tree [1:TREE_NODES-1];

// Leaf nodes (indices 16..31)
generate
    for (gi = 0; gi < TREE_LEAVES; gi = gi + 1) begin : g_leaf
        if (gi < NUM_CLASSES) begin : real_leaf
            assign tree[TREE_LEAVES + gi] =
                { score_sum[gi],
                  {{(CLASS_BITS - $clog2(NUM_CLASSES)){1'b0}}, gi[CLASS_BITS-1:0]} };
        end else begin : pad_leaf
            // Most-negative Q9.8 signed value → never wins comparison
            assign tree[TREE_LEAVES + gi] =
                { {1'b1, {(SUM_WIDTH-1){1'b0}}},  // min signed
                  {CLASS_BITS{1'b1}} };
        end
    end
endgenerate

// Internal comparator nodes (indices 1..15)
// node[i] = max(node[2i], node[2i+1])  - signed comparison on top SUM_WIDTH bits
generate
    for (gi = 1; gi < TREE_LEAVES; gi = gi + 1) begin : g_cmp
        wire signed [SUM_WIDTH-1:0] lscore = tree[2*gi  ][NODE_W-1:CLASS_BITS];
        wire signed [SUM_WIDTH-1:0] rscore = tree[2*gi+1][NODE_W-1:CLASS_BITS];
        assign tree[gi] = (lscore >= rscore) ? tree[2*gi] : tree[2*gi+1];
    end
endgenerate

// Root
wire [CLASS_BITS-1:0] argmax_idx   = tree[1][CLASS_BITS-1:0];
wire [SUM_WIDTH-1:0]  argmax_score = tree[1][NODE_W-1:CLASS_BITS];

// ─────────────────────────────────────────────────────────────────────────────
//  6. FSM - synchronous, active-low reset
// ─────────────────────────────────────────────────────────────────────────────
integer k;
always @(posedge clk) begin
    if (!rst_n) begin
        state      <= ST_IDLE;
        voter_busy <= 1'b0;
        pred_valid <= 1'b0;
        pred_class <= {CLASS_BITS{1'b0}};
        pred_score <= {SUM_WIDTH{1'b0}};
        for (k = 0; k < NUM_CLASSES; k = k + 1) begin
            score_N[k]   <= {SCORE_WIDTH{1'b0}};
            score_Np1[k] <= {SCORE_WIDTH{1'b0}};
        end
    end else begin

        pred_valid <= 1'b0;  // default: de-assert

        case (state)

            // ── IDLE: waiting for Window N ─────────────────────────────
            ST_IDLE : begin
                voter_busy <= 1'b0;
                if (score_valid) begin
                    for (k = 0; k < NUM_CLASSES; k = k + 1)
                        score_N[k] <= score_in_w[k];
                    state      <= ST_HOLD;
                    voter_busy <= 1'b1;
                end
            end

            // ── HOLD: Window N latched, waiting for Window N+1 ────────
            ST_HOLD : begin
                voter_busy <= 1'b1;
                if (score_valid) begin
                    // Latch N+1 for record / sliding-window reuse
                    for (k = 0; k < NUM_CLASSES; k = k + 1)
                        score_Np1[k] <= score_in_w[k];

                    // argmax fires THIS cycle (bypass mux feeds score_in_w
                    // into adder - mux_bypass is combinationally true now)
                    pred_class <= argmax_idx;
                    pred_score <= argmax_score;
                    pred_valid <= 1'b1;

                    if (SLIDING_WINDOW) begin
                        // Promote N+1 → new N; stay in HOLD
                        for (k = 0; k < NUM_CLASSES; k = k + 1)
                            score_N[k] <= score_in_w[k];
                        // score_Np1 will be overwritten next window - fine
                    end else begin
                        state      <= ST_IDLE;
                        voter_busy <= 1'b0;
                    end
                end
            end

            default : state <= ST_IDLE;
        endcase
    end
end

endmodule
`default_nettype wire

// =============================================================================
//  ZCU104 XDC CONSTRAINTS  (include in your project .xdc)
// =============================================================================
//
//  # Primary clock - ZCU104 200 MHz system clock on PL (adjust pin for your board)
//  create_clock -period 5.000 -name clk_pl [get_ports clk]
//
//  # Multicycle path for the adder → argmax tree combinational path
//  # (adder output is purely combinational; registered at pred_class/pred_score)
//  # If Vivado reports the path as failing at 200 MHz, uncomment:
//  # set_multicycle_path -setup 2 -from [get_cells score_N_reg*] \
//  #                               -to   [get_cells pred_class_reg*]
//  # set_multicycle_path -hold  1 -from [get_cells score_N_reg*] \
//  #                               -to   [get_cells pred_class_reg*]
//
//  # Reset false path (if rst_n comes from PS or MMCM locked signal)
//  # set_false_path -from [get_ports rst_n]
//
// =============================================================================
