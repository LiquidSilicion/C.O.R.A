`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Module: bram_arbiter
// Purpose: Priority arbiter for shared narrow BRAM bus (Bank 3 - weights)
// Priority: MAC (0) > BPTT (1) > WUPD (2) > HOST (3)
//
// CHANGE FROM PREVIOUS VERSION:
//   Address bus widened from [13:0] to [14:0] (15-bit).
//   W_out base address = 0x4800 = 18432 requires bit 14.
//   Old [13:0] truncated every W_out access into the W_rec address range.
//
// In inference-only mode all training masters (bptt/wupd/host) are tied to
// req=0 / done=1 in the top module, so the MAC always wins immediately.
////////////////////////////////////////////////////////////////////////////////

module bram_arbiter (
    input  wire        clk,
    input  wire        rst_n,

    // Master 0: MAC engine
    input  wire        mac_req,
    input  wire        mac_done,
    input  wire [14:0] mac_addr,
    input  wire [15:0] mac_din,
    input  wire        mac_we,
    output reg         mac_grant,
    output reg  [15:0] mac_dout,

    // Master 1: BPTT (tied off during inference)
    input  wire        bptt_req,
    input  wire        bptt_done,
    input  wire [14:0] bptt_addr,
    input  wire [15:0] bptt_din,
    input  wire        bptt_we,
    output reg         bptt_grant,
    output reg  [15:0] bptt_dout,

    // Master 2: Weight updater (tied off during inference)
    input  wire        wupd_req,
    input  wire        wupd_done,
    input  wire [14:0] wupd_addr,
    input  wire [15:0] wupd_din,
    input  wire        wupd_we,
    output reg         wupd_grant,
    output reg  [15:0] wupd_dout,

    // Master 3: Host/UART (tied off during inference)
    input  wire        host_req,
    input  wire        host_done,
    input  wire [14:0] host_addr,
    input  wire [15:0] host_din,
    input  wire        host_we,
    output reg         host_grant,
    output reg  [15:0] host_dout,

    // Shared BRAM port (to snn_bram_top narrow bus / bram_bus_mux)
    output reg  [14:0] bram_addr,
    output reg  [15:0] bram_din,
    output reg         bram_we,
    output reg         bram_en,
    input  wire [15:0] bram_dout
);

localparam S_IDLE = 3'd0;
localparam S_MAC  = 3'd1;
localparam S_BPTT = 3'd2;
localparam S_WUPD = 3'd3;
localparam S_HOST = 3'd4;

reg [2:0] state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= S_IDLE;
        mac_grant  <= 0; bptt_grant <= 0;
        wupd_grant <= 0; host_grant <= 0;
        bram_addr  <= 0; bram_din   <= 0;
        bram_we    <= 0; bram_en    <= 0;
        mac_dout   <= 0; bptt_dout  <= 0;
        wupd_dout  <= 0; host_dout  <= 0;
    end else begin
        // Default deasserts
        mac_grant  <= 0;
        bptt_grant <= 0;
        wupd_grant <= 0;
        host_grant <= 0;
        bram_en    <= 0;

        case (state)
            S_IDLE: begin
                if (mac_req) begin
                    state <= S_MAC;
                    mac_grant <= 1;
                    bram_addr <= mac_addr;
                    bram_din  <= mac_din;
                    bram_we   <= mac_we;
                    bram_en   <= 1;
                end else if (bptt_req) begin
                    state      <= S_BPTT;
                    bptt_grant <= 1;
                    bram_addr  <= bptt_addr;
                    bram_din   <= bptt_din;
                    bram_we    <= bptt_we;
                    bram_en    <= 1;
                end else if (wupd_req) begin
                    state      <= S_WUPD;
                    wupd_grant <= 1;
                    bram_addr  <= wupd_addr;
                    bram_din   <= wupd_din;
                    bram_we    <= wupd_we;
                    bram_en    <= 1;
                end else if (host_req) begin
                    state      <= S_HOST;
                    host_grant <= 1;
                    bram_addr  <= host_addr;
                    bram_din   <= host_din;
                    bram_we    <= host_we;
                    bram_en    <= 1;
                end
            end

            S_MAC: begin
                if (mac_done) begin
                    state <= S_IDLE;
                end else begin
                    mac_grant <= 1;
                    bram_addr <= mac_addr;
                    bram_din  <= mac_din;
                    bram_we   <= mac_we;
                    bram_en   <= 1;
                    mac_dout  <= bram_dout;
                end
            end

            S_BPTT: begin
                if (bptt_done) begin
                    state <= S_IDLE;
                end else begin
                    bptt_grant <= 1;
                    bram_addr  <= bptt_addr;
                    bram_din   <= bptt_din;
                    bram_we    <= bptt_we;
                    bram_en    <= 1;
                    bptt_dout  <= bram_dout;
                end
            end

            S_WUPD: begin
                if (wupd_done) begin
                    state <= S_IDLE;
                end else begin
                    wupd_grant <= 1;
                    bram_addr  <= wupd_addr;
                    bram_din   <= wupd_din;
                    bram_we    <= wupd_we;
                    bram_en    <= 1;
                    wupd_dout  <= bram_dout;
                end
            end

            S_HOST: begin
                if (host_done) begin
                    state <= S_IDLE;
                end else begin
                    host_grant <= 1;
                    bram_addr  <= host_addr;
                    bram_din   <= host_din;
                    bram_we    <= host_we;
                    bram_en    <= 1;
                    host_dout  <= bram_dout;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule