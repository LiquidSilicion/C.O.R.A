`timescale 1ns/1ps
// =============================================================================
// snn_bram_top.v  -  CORA Memory Subsystem  (Inference Integration)
// Target : AMD ZCU104 (XCZU7EV) @ 200 MHz
//
// This module is the single memory hub for the SNN accelerator pipeline.
// Every block that needs data - MAC engine reading weights, LIF array
// reading/writing membrane potential, MAC reading spike history for recurrent
// connections - gets it from here. The pipeline CANNOT run without this wired.
//
// ─── BANKS INCLUDED (inference needs) ────────────────────────────────────────
//  Bank 1a  V_m      16-bit × 128   LIF membrane potential (persists across windows)
//  Bank 1b  S[t]    128-bit × 512   Spike history (s_prev for W_rec recurrent pass)
//  Bank 3a  W_in     16-bit × 2048  Input weights  W_in[NI=16][NH=128]
//  Bank 3b  W_rec    16-bit × 16384 Recurrent wts  W_rec[NH=128][NH=128]
//  Bank 3c  W_out    16-bit × 2048  Output weights W_out[NH=128][NO=10] (1280 used)
//
// ─── BANKS NOT INCLUDED (TRAIN mode only, clock-gated in CMD/SLEEP per CORA v4) ─
//  Bank 0   Config registers                - static, not needed at runtime
//  Bank 1c  X[t] input activations          - BPTT ∇W_in = δ_h ⊗ X[t] only
//  Bank 1d  y[t] output activations         - BPTT loss only
//  Bank 2a  Target spike patterns           - BPTT ground truth only
//  Bank 2b  Target output labels            - BPTT loss only
//  Bank 4a/b/c  dW gradient banks          - BPTT weight gradients only
//  Bank 5   Eligibility/neuron state traces - BPTT e-prop only
//  SG LUT   Surrogate gradient LUT (σ')    - BPTT backward pass only
//
// ─── SEPARATE BRAM (not in this module) ──────────────────────────────────────
//  window_acc_bram  8-bit × 2048 True Dual Port
//  Instantiated INSIDE s10_window_accumulator. Port A = accumulator write,
//  Port B = spike_readback read. These two ports run simultaneously so it
//  MUST be True Dual Port. Not addressable from the unified bus here.
//
// ─── BUS ARCHITECTURE ────────────────────────────────────────────────────────
//  Narrow bus (16-bit, 17-bit addr): Bank 1a + Bank 3a/3b/3c
//    Driven by bram_bus_mux in top_wrapper (arbitrates MAC vs LIF).
//    MAC engine drives this when reading weights.
//    LIF array drives this when reading/writing V_m.
//    They never overlap: LIF runs during S_CAPTURE while MAC is paused.
//
//  Wide bus (128-bit, 9-bit addr): Bank 1b only
//    Driven directly by MAC engine. No arbiter needed - only MAC touches this.
//    addr_wide = timestep index t (0..49).
//    Write: after LIF capture, MAC saves lif_spikes[127:0] → S[t].
//    Read:  at start of recurrent pass, MAC loads S[t-1] → s_prev.
//
// ─── ADDRESS MAP ─────────────────────────────────────────────────────────────
//  Narrow bus (17-bit):
//    0x01000 - 0x0107F   Bank 1a  V_m     16b × 128   neurons 0..127
//    0x04000 - 0x047FF   Bank 3a  W_in    16b × 2048  ch*128 + neuron
//    0x04800 - 0x07FFF   Bank 3b  W_rec   16b × 16384 pre*128 + post
//    0x08000 - 0x084FF   Bank 3c  W_out   16b × 1280  neuron*10 + class
//                         [FIX: original had 0x083FF = only 1024 locations]
//  Wide bus (9-bit):
//    0x000 - 0x1FF        Bank 1b  S[t]   128b × 512  timestep index
//
// ─── HOW THE MAC ENGINE USES THIS ────────────────────────────────────────────
//  Forward pass (W_in × input_spikes):
//    For each input channel ch (0..15):
//      For each neuron block (0..7, each 16 wide):
//        addr = 0x04000 + ch*128 + block*16  → read 16 weights per cycle
//        If input spike[ch] fired: h_acc[neuron] += weight
//
//  Recurrent pass (W_rec × s_prev):
//    First: addr_wide = t_cnt-1 → read s_prev[127:0] from Bank 1b
//    For each pre-synaptic neuron n where s_prev[n]=1:
//      For each post-synaptic neuron block (0..7, each 16 wide):
//        addr = 0x04800 + n*128 + block*16  → read 16 weights per cycle
//        h_acc[post] += weight
//
//  After LIF capture (save spikes):
//    addr_wide = t_cnt, din_wide = lif_spikes[127:0], wea_wide = 1
//    → write S[t] to Bank 1b
//
//  Output pass (W_out × final s_prev):
//    For each hidden neuron n where s_prev[n]=1:
//      addr = 0x08000 + n*10 + 0  → read NO=10 weights (fits in 1 fetch, NO<16)
//      score[class] += weight for each class
//
// ─── HOW THE LIF ARRAY USES THIS ─────────────────────────────────────────────
//  During sweep (one neuron per 2 cycles):
//    Cycle 1: addr = 0x01000 + neuron_idx, enb=1 → read V_old from Bank 1a
//    Cycle 2: compute V_new = α·V_old + accum[neuron]
//             addr = 0x01000 + neuron_idx, wea=1, din=V_new → write Bank 1a
//    The bram_bus_mux gives the LIF array priority on the narrow bus during sweep.
// =============================================================================

module snn_bram_top (
    input  wire         clka,       // 200 MHz primary clock
    input  wire         clkb,       // 200 MHz secondary clock (tie to clka)

    // ── Narrow bus  (16-bit) ──────────────────────────────────────────────────
    input  wire         ena,        // Port A enable
    input  wire         enb,        // Port B enable
    input  wire         wea,        // Write enable (LIF array only; MAC reads only)
    input  wire [16:0]  addr,       // 17-bit unified address
    input  wire [15:0]  din,        // Write data (V_m write-back from LIF)
    output reg  [15:0]  dout,       // Read data (weight or V_m)

    // ── Wide bus  (128-bit) ───────────────────────────────────────────────────
    input  wire         ena_wide,
    input  wire         enb_wide,
    input  wire         wea_wide,
    input  wire [8:0]   addr_wide,  // Timestep index
    input  wire [127:0] din_wide,   // lif_spikes to save
    output reg  [127:0] dout_wide   // s_prev loaded for recurrent pass
);

// =============================================================================
// ADDRESS DECODE
// =============================================================================
wire sel_b1_vm   = (addr >= 17'h01000) && (addr <= 17'h0107F);
wire sel_b3_win  = (addr >= 17'h04000) && (addr <= 17'h047FF);
wire sel_b3_wrec = (addr >= 17'h04800) && (addr <= 17'h07FFF);
wire sel_b3_wout = (addr >= 17'h08000) && (addr <= 17'h084FF); // FIX: was 0x083FF

// =============================================================================
// READ DATA WIRES
// =============================================================================
wire [15:0]  dout_b1_vm;
wire [15:0]  dout_b3_win;
wire [15:0]  dout_b3_wrec;
wire [15:0]  dout_b3_wout;
wire [127:0] dout_b1_s;

// =============================================================================
// OUTPUT MUX - narrow bus
// =============================================================================
always @(*) begin
    case (1'b1)
        sel_b1_vm  : dout = dout_b1_vm;
        sel_b3_win : dout = dout_b3_win;
        sel_b3_wrec: dout = dout_b3_wrec;
        sel_b3_wout: dout = dout_b3_wout;
        default    : dout = 16'hDEAD;
    endcase
end

// =============================================================================
// OUTPUT MUX - wide bus
// =============================================================================
always @(*) begin
    dout_wide = dout_b1_s;  // Only one wide bank
end

// =============================================================================
// BANK 1a : V_m[t] - Membrane potential
// 16-bit × 128 words   →   1 × RAMB18E2
// Vivado IP: Simple Dual Port, width=16, depth=1024 (min for RAMB18 at 16b)
// Only 128 locations used (neurons 0..127)
// =============================================================================
bank1_vm u_bank1_vm (
    .clka  (clka),
    .ena   (sel_b1_vm & ena),
    .wea   (wea),
    .addra (addr[9:0]),     // neuron index 0..127
    .dina  (din),
    .clkb  (clkb),
    .enb   (sel_b1_vm & enb),
    .addrb (addr[9:0]),
    .doutb (dout_b1_vm)
);

// =============================================================================
// BANK 1b : S[t] - Spike history  (128-bit wide bus)
// 128-bit × 512 words   →   4 × RAMB36E2
// Vivado IP: Simple Dual Port, width=128, depth=512
// addr_wide = timestep index t (0..49 used for inference; 0..511 for BPTT)
// =============================================================================
bank1_s u_bank1_s (
    .clka  (clka),
    .ena   (ena_wide),
    .wea   (wea_wide),
    .addra (addr_wide),
    .dina  (din_wide),
    .clkb  (clkb),
    .enb   (enb_wide),
    .addrb (addr_wide),
    .doutb (dout_b1_s)
);

// =============================================================================
// BANK 3a : W_in - Input weights
// 16-bit × 2048 words   →   1 × RAMB36E2
// Vivado IP: Simple Dual Port, width=16, depth=2048
// Load from w_in.coe (trained weights from Python)
// addr[10:0] = ch*128 + neuron_idx (relative within bank)
// =============================================================================
bank3_win u_bank3_win (
    .clka  (clka),
    .ena   (sel_b3_win & ena),
    .wea   (wea),           // Always 0 during inference
    .addra (addr[10:0]),
    .dina  (din),
    .clkb  (clkb),
    .enb   (sel_b3_win & enb),
    .addrb (addr[10:0]),
    .doutb (dout_b3_win)
);

// =============================================================================
// BANK 3b : W_rec - Recurrent weights
// 16-bit × 16384 words   →   8 × RAMB36E2  (Vivado cascades automatically)
// Vivado IP: Simple Dual Port, width=16, depth=16384
// Load from w_rec.coe (trained weights from Python)
// addr[13:0] = pre_neuron*128 + post_neuron (relative within bank)
// =============================================================================
bank3_wrec u_bank3_wrec (
    .clka  (clka),
    .ena   (sel_b3_wrec & ena),
    .wea   (wea),
    .addra (addr[13:0]),
    .dina  (din),
    .clkb  (clkb),
    .enb   (sel_b3_wrec & enb),
    .addrb (addr[13:0]),
    .doutb (dout_b3_wrec)
);

// =============================================================================
// BANK 3c : W_out - Output weights
// 16-bit × 2048 words IP   →   1 × RAMB36E2
// Only 1280 of 2048 locations used (NH=128 × NO=10)
// Vivado IP: Simple Dual Port, width=16, depth=2048
// Load from w_out.coe
// addr[10:0] = neuron*10 + class_idx (relative within bank)
// =============================================================================
bank3_wout u_bank3_wout (
    .clka  (clka),
    .ena   (sel_b3_wout & ena),
    .wea   (wea),
    .addra (addr[10:0]),
    .dina  (din),
    .clkb  (clkb),
    .enb   (sel_b3_wout & enb),
    .addrb (addr[10:0]),
    .doutb (dout_b3_wout)
);

endmodule