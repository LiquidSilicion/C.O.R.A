`timescale 1ns/1ps
// =============================================================================
// top_wrapper.v  —  Full Integration: SNN Accelerator + BRAM Subsystem
// Target: AMD ZCU104 (XCZU7EV) @ 200 MHz
//
// This is the top-level module that integrates:
//   1. snn_bram_top         — memory subsystem (all 5 inference banks)
//   2. snn_accelerator_top  — inference pipeline (AER→MAC→LIF→Output)
//   3. bram_bus_mux         — arbitrates narrow BRAM bus between MAC and LIF
//
// ─── HOW DATA FLOWS THROUGH THE INTEGRATION ──────────────────────────────────
//
//  WEIGHTS (Bank 3a/3b/3c) → MAC engine:
//    snn_accelerator_top exposes bram_bank3_addr[14:0] + bram_bank3_dout.
//    The MAC engine drives bram_bank3_addr.
//    We translate: unified_addr = 0x04000 + mac_addr (for W_in region).
//    But mac_engine_parallel already outputs unified 17-bit addresses,
//    so we zero-extend mac_bram_addr[14:0] → 17-bit and feed directly.
//    The read data bram_dout [15:0] goes back as mac_bram_dout.
//
//  V_m (Bank 1a) ↔ LIF array:
//    lif_array_bram_fixed exposes vm_addr[8:0] (uses [6:0] for 128 neurons),
//    vm_din, vm_dout, vm_we, vm_en.
//    bram_bus_mux translates: unified_addr = 0x01000 | vm_addr[6:0].
//    Read data bram_dout → vm_dout when LIF owns bus.
//
//  S[t] spike history (Bank 1b) ↔ MAC engine:
//    MAC engine needs a separate 128-bit wide port to save/load s_prev.
//    In mac_engine_parallel this is currently a 128-bit register (s_prev).
//    Here we expose the wide bus and wire it to Bank 1b.
//    MAC writes lif_spikes → Bank 1b after each LIF capture.
//    MAC reads s_prev ← Bank 1b before each recurrent pass.
//    addr_wide = t_cnt (current timestep index).
//
// ─── PORT CHANGES vs ORIGINAL snn_accelerator_top ────────────────────────────
//  The original top had:
//    bram_bank3_addr[13:0]  — 14-bit, can only address 16384 locations.
//                             W_out starts at offset 0x4800 within Bank 3 unified
//                             space, which means the absolute address can exceed
//                             14 bits. Fixed to [14:0] = 15-bit.
//    bram_bank2_addr[8:0]   — 9-bit for V_m. Only [6:0] used (128 neurons).
//                             Left as-is; upper bits unused.
//
// ─── BUS TIMING ──────────────────────────────────────────────────────────────
//  Narrow bus (to snn_bram_top):
//    Cycle N:   MAC/LIF drives addr
//    Cycle N+1: bram_dout is valid
//    MAC engine accounts for 1-cycle latency in S_FETCH state.
//    LIF array accounts for 1-cycle latency in ST_READ→ST_WRITE transition.
//
//  Wide bus (to Bank 1b):
//    Same 1-cycle latency. MAC engine adds 1 wait state before using dout_wide.
//
// =============================================================================

module top_wrapper (
    input  wire        clk_in,    // 200 MHz from MMCM
    input  wire        rst_n,     // Active-low synchronous reset

    // ── AER Input (from cochlea / GPIO) ──────────────────────────────────────
    input  wire        aer_valid,
    input  wire [23:0] aer_data,  // [23:20]=ch, [19:0]=timestamp

    // ── VAD gate ─────────────────────────────────────────────────────────────
    input  wire        speech_valid,

    // ── Classification outputs ────────────────────────────────────────────────
    output wire        window_ready,
    output wire        result_valid,
    output wire [3:0]  cmd_id,
    output wire [7:0]  confidence
);

// =============================================================================
// CLOCK
// =============================================================================
wire clka = clk_in;
wire clkb = clk_in;   // Single clock domain; both ports same clock

// =============================================================================
// NARROW BUS SIGNALS  (between bram_bus_mux and snn_bram_top)
// =============================================================================
wire [16:0] bram_addr;
wire [15:0] bram_din;
wire        bram_we;
wire        bram_ena;
wire        bram_enb;
wire [15:0] bram_dout;

// =============================================================================
// WIDE BUS SIGNALS  (MAC engine ↔ Bank 1b S[t])
// =============================================================================
wire         bram_ena_wide;
wire         bram_enb_wide;
wire         bram_wea_wide;
wire [8:0]   bram_addr_wide;
wire [127:0] bram_din_wide;
wire [127:0] bram_dout_wide;

// =============================================================================
// MAC ENGINE BRAM INTERFACE  (from snn_accelerator_top internal signals)
// =============================================================================
// mac_engine_parallel outputs 15-bit unified weight addresses.
// Absolute addresses:
//   W_in  base = 0x04000 → bit 14 is 0, bits 13:0 = 0x0000..0x07FF
//   W_rec base = 0x04800 → bit 14 is 0, bits 13:0 = 0x0800..0x47FF
//   W_out base = 0x08000 → bit 15 would be needed!
//
// IMPORTANT: 0x08000 = 32768. This needs 16 bits, not 15.
// Fix: snn_accelerator_top and mac_engine_parallel must use [15:0] for addr.
// Here we zero-extend [15:0] → [16:0] for the 17-bit unified bus.
wire [15:0] mac_bram_addr_16;   // From snn_accelerator_top (extended)
wire [15:0] mac_bram_dout_16;   // Weight data back to MAC
wire        mac_bram_grant;     // Grant from arbiter inside snn_accelerator_top

// Convert 16-bit MAC address to 17-bit unified bus address
// The MAC engine already encodes base offsets (0x04000, 0x04800, 0x08000)
// into its address, so we just zero-extend.
wire [16:0] mac_bram_addr_17 = {1'b0, mac_bram_addr_16};

// =============================================================================
// LIF ARRAY BRAM INTERFACE  (from snn_accelerator_top vm_* ports)
// =============================================================================
wire [8:0]  vm_addr_9;    // 9-bit from lif_array; only [6:0] = neuron_idx used
wire [15:0] vm_din_16;
wire [15:0] vm_dout_16;
wire        vm_we;
wire        vm_en;

// =============================================================================
// BRAM BUS MUX  (LIF has priority over MAC on narrow bus)
// =============================================================================
bram_bus_mux u_mux (
    // MAC side
    .mac_addr       (mac_bram_addr_17),
    .mac_din        (16'd0),           // MAC never writes weights
    .mac_we         (1'b0),
    .mac_ena        (mac_bram_grant),  // Only active when arbiter grants
    .mac_enb        (mac_bram_grant),

    // LIF side
    .lif_neuron_idx (vm_addr_9[6:0]),  // 7-bit neuron index
    .lif_din        (vm_din_16),
    .lif_we         (vm_we),
    .lif_ena        (vm_en),
    .lif_enb        (vm_en),           // LIF reads and writes through ena

    // To BRAM
    .bram_addr      (bram_addr),
    .bram_din       (bram_din),
    .bram_we        (bram_we),
    .bram_ena       (bram_ena),
    .bram_enb       (bram_enb),

    // Read data routing
    .bram_dout      (bram_dout),
    .mac_dout       (mac_bram_dout_16),
    .lif_dout       (vm_dout_16)
);

// =============================================================================
// snn_bram_top  —  Memory subsystem
// =============================================================================
snn_bram_top u_bram (
    .clka       (clka),
    .clkb       (clkb),

    // Narrow bus
    .ena        (bram_ena),
    .enb        (bram_enb),
    .wea        (bram_we),
    .addr       (bram_addr),
    .din        (bram_din),
    .dout       (bram_dout),

    // Wide bus (S[t] spike history)
    .ena_wide   (bram_ena_wide),
    .enb_wide   (bram_enb_wide),
    .wea_wide   (bram_wea_wide),
    .addr_wide  (bram_addr_wide),
    .din_wide   (bram_din_wide),
    .dout_wide  (bram_dout_wide)
);

// =============================================================================
// snn_accelerator_top  —  Inference pipeline
// =============================================================================
snn_accelerator_top u_snn (
    .clk_200m        (clk_in),
    .rst_n           (rst_n),

    // AER
    .aer_valid       (aer_valid),
    .aer_data        (aer_data),
    .speech_valid    (speech_valid),

    // Results
    .window_ready    (window_ready),
    .result_valid    (result_valid),
    .cmd_id          (cmd_id),
    .confidence      (confidence),

    // BRAM Bank 3 — weights (narrow bus, read by MAC engine)
    // snn_accelerator_top drives bram_bank3_addr; we route through bram_bus_mux
    .bram_bank3_addr (mac_bram_addr_16),   // MAC drives this [15:0]
    .bram_bank3_dout (mac_bram_dout_16),   // Weight data from BRAM → MAC
    .bram_bank3_din  (),                   // Unused — inference only (no weight writes)
    .bram_bank3_we   (),                   // Unused
    .bram_bank3_en   (mac_bram_grant),     // Driven by arbiter inside snn_accelerator_top

    // BRAM Bank 2 — V_m (narrow bus, read/write by LIF array)
    // LIF array drives vm_addr, vm_din, vm_we, vm_en
    .bram_bank2_addr (vm_addr_9),          // [8:0] from LIF; only [6:0] meaningful
    .bram_bank2_dout (vm_dout_16),         // V_old read from Bank 1a → LIF
    .bram_bank2_din  (vm_din_16),          // V_new from LIF → Bank 1a write
    .bram_bank2_we   (vm_we),
    .bram_bank2_en   (vm_en)
);

// =============================================================================
// WIDE BUS: Connect MAC engine's s_prev interface to Bank 1b
//
// mac_engine_parallel needs two new ports added to snn_accelerator_top
// to expose the wide bus. Until those ports are added, the fallback is:
//   s_prev stays as a 128-bit register inside mac_engine_parallel (current design).
//   The wide bus ports are tied off here and Bank 1b holds a copy for future BPTT.
//
// When you add the ports to snn_accelerator_top and mac_engine_parallel,
// wire them here:
//   .mac_spk_we    → bram_wea_wide
//   .mac_spk_addr  → bram_addr_wide
//   .mac_spk_din   → bram_din_wide
//   .mac_spk_dout  ← bram_dout_wide
// =============================================================================
assign bram_ena_wide  = 1'b0;   // TODO: connect to MAC engine wide port
assign bram_enb_wide  = 1'b0;
assign bram_wea_wide  = 1'b0;
assign bram_addr_wide = 9'd0;
assign bram_din_wide  = 128'd0;
// bram_dout_wide left unconnected until MAC ports added

endmodule
