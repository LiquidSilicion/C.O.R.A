`timescale 1ns/1ps
// =============================================================================
// s10_window_accumulator.v  -  v9
//
// Port A = NO_CHANGE mode: douta only valid after a pure read cycle.
// After any write, douta is indeterminate.
//
// FIX from v8: shadow register is now STICKY (not a 1-cycle pulse).
// shd_valid stays asserted until a new write updates it or reset.
// This ensures forwarding works regardless of how many cycles elapse
// between a write and the next read of the same address.
//
// PIPELINE:
//   no do_b  (bin <  25): 3 cycles min
//   do_b     (bin >= 25): 5 cycles min (write-A, read-B, write-B)
// =============================================================================
module s10_window_accumulator (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [19:0] window_offset,
    input  wire        ts_abs_valid,
    input  wire [3:0]  spike_ch,
    input  wire        speech_valid,
    output reg         window_open,
    output reg         window_ready,
    output reg         rd_ping_sel,
    input  wire [10:0] mac_rd_addr,
    output wire [7:0]  mac_rd_data
);

localparam EMIT_BIN = 6'd49;
localparam OVL_OFF  = 6'd25;
localparam MAX_CNT  = 8'hFF;
localparam CLR_MAX  = 11'd1599;

localparam GATED = 2'd0;
localparam ACCUM = 2'd1;
localparam EMIT  = 2'd2;
localparam CLEAR = 2'd3;

localparam PH_WR_A = 2'd0;
localparam PH_RD_B = 2'd1;
localparam PH_WR_B = 2'd2;

reg [1:0] state;
reg       ping_sel;
reg       clear_ping;

wire [5:0] bin_a     = window_offset[9:4];
wire       bin_valid = (bin_a <= EMIT_BIN);
wire       do_emit   = ts_abs_valid && (bin_a == EMIT_BIN) && speech_valid;
wire       bin_b_en  = (bin_a >= OVL_OFF);
wire [5:0] bin_b     = bin_a - OVL_OFF;

// ---- BRAM ----
reg        bram_ena;
reg        bram_wea;
reg [10:0] bram_addra;
reg  [7:0] bram_dina;
wire [7:0] bram_douta;

window_acc_bram u_bram (
    .clka (clk),        .ena  (bram_ena),  .wea  (bram_wea),
    .addra(bram_addra), .dina (bram_dina), .douta(bram_douta),
    .clkb (clk),        .enb  (1'b1),      .web  (1'b0),
    .addrb(mac_rd_addr),.dinb (8'd0),      .doutb(mac_rd_data)
);

// ---- Stage 0: read in flight ----
reg        s0_valid;
reg [10:0] s0_addr_a;
reg        s0_do_b;
reg [10:0] s0_addr_b;

// ---- Stage 1: write-back ----
reg        s1_valid;
reg [1:0]  s1_ph;
reg [10:0] s1_addr_a;
reg  [7:0] s1_val_a;
reg        s1_do_b;
reg [10:0] s1_addr_b;

// ---- Shadow register (STICKY) ----
// Holds the last written address+value.
// shd_valid stays 1 until reset or EMIT (not a pulse).
// This ensures forwarding works even when several cycles elapse
// between consecutive spikes to the same address (TC8, TC9).
reg [10:0] shd_addr;
reg  [7:0] shd_val;
reg        shd_valid;

// Forwarding: when s0->s1 transition latches douta, check if the
// address being read was the last one written. If so, use shadow.
wire       use_shadow = shd_valid && (s0_addr_a == shd_addr);
wire [7:0] cur_val    = use_shadow ? shd_val : bram_douta;
wire [7:0] inc_a      = (cur_val    == MAX_CNT) ? MAX_CNT : cur_val    + 8'd1;
wire [7:0] inc_b      = (bram_douta == MAX_CNT) ? MAX_CNT : bram_douta + 8'd1;

wire pipe_busy = s0_valid || s1_valid;

// ---- CLEAR counters ----
reg [10:0] clr_cnt;
reg [3:0]  clr_ch;
reg [5:0]  clr_bin;

always @(posedge clk) begin
    if (!reset_n) begin
        state        <= GATED;
        ping_sel     <= 0; rd_ping_sel <= 1; clear_ping <= 0;
        window_ready <= 0; window_open <= 0;
        bram_ena     <= 0; bram_wea <= 0; bram_addra <= 0; bram_dina <= 0;
        s0_valid     <= 0; s0_addr_a <= 0; s0_do_b <= 0; s0_addr_b <= 0;
        s1_valid     <= 0; s1_ph <= 0;
        s1_addr_a    <= 0; s1_val_a <= 0; s1_do_b <= 0; s1_addr_b <= 0;
        shd_addr     <= 0; shd_val <= 0; shd_valid <= 0;
        clr_cnt      <= 0; clr_ch <= 0; clr_bin <= 0;
    end else begin
        window_ready <= 0;
        window_open  <= 0;
        bram_wea     <= 0;
        bram_ena     <= 0;
        // NOTE: shd_valid is NOT cleared here - it is sticky

        case (state)

            GATED: if (speech_valid) state <= ACCUM;

            ACCUM: begin

                // ============================================================
                // STAGE 1 write-back FSM
                // ============================================================
                if (s1_valid) begin
                    case (s1_ph)

                        PH_WR_A: begin
                            bram_ena   <= 1;
                            bram_wea   <= 1;
                            bram_addra <= s1_addr_a;
                            bram_dina  <= s1_val_a;
                            // Update sticky shadow
                            shd_addr   <= s1_addr_a;
                            shd_val    <= s1_val_a;
                            shd_valid  <= 1;
                            if (s1_do_b)
                                s1_ph    <= PH_RD_B;
                            else
                                s1_valid <= 0;
                        end

                        PH_RD_B: begin
                            // Present B addr for read; douta valid next cycle
                            bram_ena   <= 1;
                            bram_wea   <= 0;
                            bram_addra <= s1_addr_b;
                            s1_ph      <= PH_WR_B;
                        end

                        PH_WR_B: begin
                            // douta now has B's current value
                            bram_ena   <= 1;
                            bram_wea   <= 1;
                            bram_addra <= s1_addr_b;
                            bram_dina  <= inc_b;
                            // Update sticky shadow to B's new value
                            shd_addr   <= s1_addr_b;
                            shd_val    <= inc_b;
                            shd_valid  <= 1;
                            s1_valid   <= 0;
                            s1_ph      <= PH_WR_A;
                        end

                        default: s1_valid <= 0;
                    endcase
                end

                // ============================================================
                // S0 -> S1: douta is valid this cycle (read issued last cycle)
                // ============================================================
                if (s0_valid && !s1_valid) begin
                    s1_valid  <= 1;
                    s1_ph     <= PH_WR_A;
                    s1_addr_a <= s0_addr_a;
                    s1_val_a  <= inc_a;   // uses sticky shadow forwarding
                    s1_do_b   <= s0_do_b;
                    s1_addr_b <= s0_addr_b;
                    s0_valid  <= 0;
                end

                // ============================================================
                // Accept spike -> issue A read
                // ============================================================
                if (ts_abs_valid && bin_valid && !do_emit && !pipe_busy) begin
                    bram_ena   <= 1;
                    bram_wea   <= 0;
                    bram_addra <= {ping_sel, spike_ch, bin_a};
                    s0_valid   <= 1;
                    s0_addr_a  <= {ping_sel, spike_ch, bin_a};
                    s0_do_b    <= bin_b_en;
                    s0_addr_b  <= {~ping_sel, spike_ch, bin_b};
                end

                if (!speech_valid) begin
                    s0_valid  <= 0; s1_valid <= 0; s1_ph <= 0;
                    shd_valid <= 0;
                    state     <= GATED;
                end else if (do_emit) begin
                    state <= EMIT;
                end
            end

            EMIT: begin
                window_ready <= 1;
                window_open  <= 1;
                rd_ping_sel  <= ping_sel;
                clear_ping   <= ping_sel;
                ping_sel     <= ~ping_sel;
                clr_cnt <= 0; clr_ch <= 0; clr_bin <= 0;
                s0_valid  <= 0; s1_valid <= 0; s1_ph <= 0;
                shd_valid <= 0;   // clear shadow on buffer switch
                state <= CLEAR;
            end

            CLEAR: begin
                bram_ena   <= 1;
                bram_wea   <= 1;
                bram_addra <= {clear_ping, clr_ch, clr_bin};
                bram_dina  <= 8'd0;
                if (clr_cnt[0]) begin
                    if (clr_bin == 6'd49) begin
                        clr_bin <= 0;
                        clr_ch  <= clr_ch + 1;
                    end else begin
                        clr_bin <= clr_bin + 1;
                    end
                end
                clr_cnt <= clr_cnt + 1;
                if (clr_cnt == CLR_MAX) state <= ACCUM;
            end

        endcase
    end
end
endmodule
