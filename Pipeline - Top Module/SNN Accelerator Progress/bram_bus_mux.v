`timescale 1ns/1ps
// =============================================================================
// bram_bus_mux.v  -  Narrow BRAM bus arbiter: MAC engine vs LIF array
// Target: AMD ZCU104 @ 200 MHz
//
// WHY THIS EXISTS:
//   The narrow bus (16-bit data, 17-bit addr) is shared between two masters:
//     1. MAC engine  - reads W_in, W_rec, W_out  (addresses 0x04000..0x084FF)
//     2. LIF array   - reads/writes V_m          (addresses 0x01000..0x0107F)
//
//   They CANNOT overlap in time because:
//     - MAC writes lif_acc to the LIF accumulator array (local regs) then asserts
//       lif_capture. During the LIF sweep (ST_SWEEP in lif_array_bram_fixed),
//       the MAC engine is in S_CAPTURE state - it is NOT issuing weight addresses.
//     - So the two masters are mutually exclusive by FSM design.
//
//   This mux formalises that: when lif_vm_en is high (LIF sweep active),
//   the LIF array gets the bus. Otherwise the MAC engine drives it.
//
// SIGNAL NAMING:
//   mac_*    - from mac_engine_parallel (weight reads)
//   lif_*    - from lif_array_bram_fixed (V_m read/write)
//   bram_*   - to snn_bram_top narrow bus
// =============================================================================

module bram_bus_mux (
    // ── MAC engine inputs ─────────────────────────────────────────────────────
    input  wire [16:0]  mac_addr,       // Weight address (17-bit unified)
    input  wire [15:0]  mac_din,        // Always 0 (MAC never writes)
    input  wire         mac_we,         // Always 0
    input  wire         mac_ena,        // Port A enable from MAC
    input  wire         mac_enb,        // Port B enable from MAC

    // ── LIF array inputs ──────────────────────────────────────────────────────
    input  wire [6:0]   lif_neuron_idx, // Neuron index 0..127 (raw from LIF)
    input  wire [15:0]  lif_din,        // V_new to write (or 0 on fire)
    input  wire         lif_we,         // vm_we from LIF FSM
    input  wire         lif_ena,        // vm_en from LIF FSM (high during sweep)
    input  wire         lif_enb,        // LIF read enable

    // ── Muxed outputs → snn_bram_top narrow bus ───────────────────────────────
    output wire [16:0]  bram_addr,
    output wire [15:0]  bram_din,
    output wire         bram_we,
    output wire         bram_ena,
    output wire         bram_enb,

    // ── Read data back to correct master ─────────────────────────────────────
    input  wire [15:0]  bram_dout,      // From snn_bram_top
    output wire [15:0]  mac_dout,       // Weight data → MAC engine
    output wire [15:0]  lif_dout        // V_old → LIF array
);

// LIF has priority when its sweep is active
wire lif_active = lif_ena;

// Address: LIF uses Bank 1a base 0x01000 + neuron_idx
// MAC uses its own pre-computed 17-bit unified address
assign bram_addr = lif_active
                 ? (17'h01000 | {10'b0, lif_neuron_idx})
                 : mac_addr;

assign bram_din  = lif_active ? lif_din  : mac_din;
assign bram_we   = lif_active ? lif_we   : mac_we;
assign bram_ena  = lif_active ? lif_ena  : mac_ena;
assign bram_enb  = lif_active ? lif_enb  : mac_enb;

// Read data goes to whichever master owns the bus
// (previous cycle's dout corresponds to previous cycle's addr owner)
assign lif_dout  = lif_active ? bram_dout : 16'h0;
assign mac_dout  =              bram_dout;          // MAC reads whatever comes back

endmodule