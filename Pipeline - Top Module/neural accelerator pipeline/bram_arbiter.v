`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: bram_arbiter
// Purpose: Priority arbiter for shared BRAM Bank 3 (Weights)
// Priority: MAC (0) > BPTT (1) > W_UPD (2) > HOST (3)
// Spec: MAC requests always win within 1 cycle (inference never stalls)
//////////////////////////////////////////////////////////////////////////////////

module bram_arbiter #(
    parameter ADDR_WIDTH = 14,  // For 16K depth BRAM
    parameter DATA_WIDTH = 16   // Q8.8 weights
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ── Master 0: MAC Engine (HIGHEST PRIORITY - INFERENCE) ──
    input  wire                 mac_req,
    output wire                 mac_grant,
    input  wire                 mac_done,
    input  wire [ADDR_WIDTH-1:0] mac_addr,
    input  wire [DATA_WIDTH-1:0] mac_din,
    input  wire                 mac_we,
    output wire [DATA_WIDTH-1:0] mac_dout,

    // ── Master 1: BPTT Engine (TRAINING) ──
    input  wire                 bptt_req,
    output wire                 bptt_grant,
    input  wire                 bptt_done,
    input  wire [ADDR_WIDTH-1:0] bptt_addr,
    input  wire [DATA_WIDTH-1:0] bptt_din,
    input  wire                 bptt_we,
    output wire [DATA_WIDTH-1:0] bptt_dout,

    // ── Master 2: Weight Updater (TRAINING) ──
    input  wire                 wupd_req,
    output wire                 wupd_grant,
    input  wire                 wupd_done,
    input  wire [ADDR_WIDTH-1:0] wupd_addr,
    input  wire [DATA_WIDTH-1:0] wupd_din,
    input  wire                 wupd_we,
    output wire [DATA_WIDTH-1:0] wupd_dout,

    // ── Master 3: HOST / UART (CONFIG) ──
    input  wire                 host_req,
    output wire                 host_grant,
    input  wire                 host_done,
    input  wire [ADDR_WIDTH-1:0] host_addr,
    input  wire [DATA_WIDTH-1:0] host_din,
    input  wire                 host_we,
    output wire [DATA_WIDTH-1:0] host_dout,

    // ── BRAM Interface (Single Port to Physical BRAM) ──
    output wire [ADDR_WIDTH-1:0] bram_addr,
    output wire [DATA_WIDTH-1:0] bram_din,
    input  wire [DATA_WIDTH-1:0] bram_dout,
    output wire                 bram_we,
    output wire                 bram_en
);

// ================================================================
// INTERNAL STATE
// ================================================================
reg         busy;
reg [1:0]   active_master;      // 0=MAC, 1=BPTT, 2=WUPD, 3=HOST

// Priority encoder: MAC always wins if requesting
wire [1:0]  priority_sel;
assign priority_sel = mac_req  ? 2'd0 :
                      bptt_req ? 2'd1 :
                      wupd_req ? 2'd2 : 2'd3;

// ================================================================
// ARBITRATION FSM
// ================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy          <= 1'b0;
        active_master <= 2'd0;
    end else begin
        // Grant bus to highest priority requester when idle
        if (!busy && (mac_req || bptt_req || wupd_req || host_req)) begin
            active_master <= priority_sel;
            busy          <= 1'b1;
        end
        // Release bus when current master asserts done
        else if (busy) begin
            case (active_master)
                2'd0: if (mac_done)  busy <= 1'b0;
                2'd1: if (bptt_done) busy <= 1'b0;
                2'd2: if (wupd_done) busy <= 1'b0;
                2'd3: if (host_done) busy <= 1'b0;
                default: busy <= 1'b0;
            endcase
        end
    end
end

// ================================================================
// GRANT SIGNALS (1-cycle latency for MAC)
// ================================================================
assign mac_grant  = busy && (active_master == 2'd0);
assign bptt_grant = busy && (active_master == 2'd1);
assign wupd_grant = busy && (active_master == 2'd2);
assign host_grant = busy && (active_master == 2'd3);

// ================================================================
// BRAM SIGNAL MUX (Address/Data/Write)
// ================================================================
assign bram_addr = (active_master == 2'd0) ? mac_addr  :
                   (active_master == 2'd1) ? bptt_addr :
                   (active_master == 2'd2) ? wupd_addr : host_addr;

assign bram_din  = (active_master == 2'd0) ? mac_din  :
                   (active_master == 2'd1) ? bptt_din :
                   (active_master == 2'd2) ? wupd_din : host_din;

assign bram_we   = (active_master == 2'd0) ? mac_we  :
                   (active_master == 2'd1) ? bptt_we :
                   (active_master == 2'd2) ? wupd_we : host_we;

assign bram_en   = busy;  // Enable BRAM only during active transaction

// ================================================================
// READ DATA DEMUX (Route BRAM output to granted master)
// ================================================================
assign mac_dout  = (active_master == 2'd0) ? bram_dout : {DATA_WIDTH{1'b0}};
assign bptt_dout = (active_master == 2'd1) ? bram_dout : {DATA_WIDTH{1'b0}};
assign wupd_dout = (active_master == 2'd2) ? bram_dout : {DATA_WIDTH{1'b0}};
assign host_dout = (active_master == 2'd3) ? bram_dout : {DATA_WIDTH{1'b0}};

endmodule
