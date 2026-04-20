`timescale 1ns/1ps
// =============================================================================
// s10_window_accumulator.v - CORA Stage 10 - v7 (fixed)
//
// PIPELINE TIMING:
//
// Clk N:   spike -> issue A read (s0 fires), s0_valid <= 1
// Clk N+1: douta has A value; s0->s1: capture inc_a, s1_valid<=1, s0_valid<=0
//          s1_b_phase=0: write A back
//          if do_b: s1_b_phase<=1 (stay in s1)
// Clk N+2: [do_b only] s1_b_phase=1: issue B read addr (wea=0)
//          s1_b_phase<=2
// Clk N+3: [do_b only] s1_b_phase=2: douta has B value, write B back
//          s1_valid<=0, s1_b_phase<=0
//
// pipe_busy = s0_valid || s1_valid
// Min gap between spikes (no do_b): 3 cycles
// Min gap between spikes (do_b):    5 cycles
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

reg [1:0] state;
reg       ping_sel;
reg       clear_ping;

wire [5:0] bin_a     = window_offset[9:4];
wire       bin_valid = (bin_a <= EMIT_BIN);
wire       do_emit   = ts_abs_valid && (bin_a == EMIT_BIN) && speech_valid;
wire       bin_b_en  = (bin_a >= OVL_OFF);
wire [5:0] bin_b     = bin_a - OVL_OFF;

// ---- BRAM Port A ----
reg        bram_ena;
reg        bram_wea;
reg [10:0] bram_addra;
reg  [7:0] bram_dina;
wire [7:0] bram_douta;

window_acc_bram u_bram (
    .clka(clk), .ena(bram_ena), .wea(bram_wea),
    .addra(bram_addra), .dina(bram_dina), .douta(bram_douta),
    .clkb(clk), .enb(1'b1), .web(1'b0),
    .addrb(mac_rd_addr), .dinb(8'd0), .doutb(mac_rd_data)
);

// ---- Pipeline stage 0: A read in flight ----
reg        s0_valid;
reg [10:0] s0_addr_a;
reg        s0_do_b;
reg [10:0] s0_addr_b;

// ---- Pipeline stage 1 ----
// s1_b_phase: 0=write A, 1=read B addr, 2=write B
reg        s1_valid;
reg [1:0]  s1_b_phase;   // FIX: was 1-bit, now 2-bit for 3-phase B handling
reg [10:0] s1_addr_a;
reg  [7:0] s1_inc_a;
reg        s1_do_b;
reg [10:0] s1_addr_b;

// ---- Forwarding ----
// If s1 is writing A this cycle and the new s0 read hits the same address,
// use s1_inc_a (the value being written) instead of stale bram_douta
wire fwd_a = s0_valid && s1_valid && (s1_b_phase == 2'd0) &&
             (s1_addr_a == s0_addr_a);
wire [7:0] douta_or_fwd = fwd_a ? s1_inc_a : bram_douta;
wire [7:0] inc_a = (douta_or_fwd == MAX_CNT) ? MAX_CNT : (douta_or_fwd + 8'd1);
wire [7:0] inc_b = (bram_douta   == MAX_CNT) ? MAX_CNT : (bram_douta   + 8'd1);

wire pipe_busy = s0_valid || s1_valid;

// ---- CLEAR counters ----
reg [10:0] clr_cnt;
reg [3:0]  clr_ch;
reg [5:0]  clr_bin;

always @(posedge clk) begin
    if (!reset_n) begin
        state       <= GATED; ping_sel <= 0; rd_ping_sel <= 1; clear_ping <= 0;
        window_ready<= 0; window_open <= 0;
        bram_ena    <= 0; bram_wea <= 0; bram_addra <= 0; bram_dina <= 0;
        s0_valid    <= 0; s0_addr_a <= 0; s0_do_b <= 0; s0_addr_b <= 0;
        s1_valid    <= 0; s1_b_phase <= 0; s1_addr_a <= 0; s1_inc_a <= 0;
        s1_do_b     <= 0; s1_addr_b <= 0;
        clr_cnt     <= 0; clr_ch <= 0; clr_bin <= 0;
    end else begin
        window_ready <= 0;
        window_open  <= 0;
        bram_wea     <= 0;
        bram_ena     <= 0;

        case (state)

            GATED: if (speech_valid) state <= ACCUM;

            ACCUM: begin

                // ==============================================================
                // STAGE 1 processing  (3-phase when do_b=1)
                //
                // Phase 0: Write A back.
                //          If do_b, move to phase 1 (stay in s1).
                //          Else, clear s1_valid (done).
                //
                // Phase 1: Issue B read (wea=0, present s1_addr_b).
                //          Move to phase 2.
                //          NOTE: do NOT touch s1_valid here.
                //
                // Phase 2: douta now has B value. Write B back.
                //          Clear s1_valid (done).
                //
                // KEY FIX: Phase 0 and Phase 1 are now separate clock cycles.
                // Previously bram_wea<=0 inside the do_b branch was overriding
                // the bram_wea<=1 set for the A write, so A was never written
                // when do_b=1.
                // ==============================================================
                if (s1_valid) begin
                    case (s1_b_phase)

                        2'd0: begin
                            // Write A
                            bram_ena   <= 1;
                            bram_wea   <= 1;
                            bram_addra <= s1_addr_a;
                            bram_dina  <= s1_inc_a;
                            if (s1_do_b)
                                s1_b_phase <= 2'd1;   // next cycle: read B
                            else
                                s1_valid   <= 0;      // done
                        end

                        2'd1: begin
                            // Read B address (bram output will be valid next cycle)
                            bram_ena   <= 1;
                            bram_wea   <= 0;
                            bram_addra <= s1_addr_b;
                            s1_b_phase <= 2'd2;
                        end

                        2'd2: begin
                            // Write B (bram_douta now has B value)
                            bram_ena   <= 1;
                            bram_wea   <= 1;
                            bram_addra <= s1_addr_b;
                            bram_dina  <= inc_b;
                            s1_valid   <= 0;
                            s1_b_phase <= 2'd0;
                        end

                        default: s1_valid <= 0;
                    endcase
                end

                // ==============================================================
                // STAGE 0 -> STAGE 1 transition
                // s0_valid=1 means A read addr was presented last cycle,
                // so bram_douta is valid this cycle.
                // Only transition when s1 is free (s1_valid=0).
                // ==============================================================
                if (s0_valid && !s1_valid) begin
                    s1_valid   <= 1;
                    s1_addr_a  <= s0_addr_a;
                    s1_inc_a   <= inc_a;        // uses forwarded douta_or_fwd
                    s1_do_b    <= s0_do_b;
                    s1_addr_b  <= s0_addr_b;
                    s1_b_phase <= 2'd0;
                    s0_valid   <= 0;
                end

                // ==============================================================
                // Accept new spike -> issue A read (stage 0)
                // Guard: pipe_busy must be clear, not an emit spike
                // ==============================================================
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
                    s0_valid<=0; s1_valid<=0; s1_b_phase<=2'd0;
                    state<=GATED;
                end else if (do_emit) begin
                    state<=EMIT;
                end
            end

            EMIT: begin
                window_ready <= 1;
                window_open  <= 1;
                rd_ping_sel  <= ping_sel;
                clear_ping   <= ping_sel;
                ping_sel     <= ~ping_sel;
                clr_cnt<=0; clr_ch<=0; clr_bin<=0;
                s0_valid<=0; s1_valid<=0; s1_b_phase<=2'd0;
                state<=CLEAR;
            end

            CLEAR: begin
                bram_ena   <= 1;
                bram_wea   <= 1;
                bram_addra <= {clear_ping, clr_ch, clr_bin};
                bram_dina  <= 8'd0;
                if (clr_cnt[0]) begin
                    if (clr_bin == 6'd49) begin
                        clr_bin <= 0; clr_ch <= clr_ch + 1;
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
