// =============================================================================
//  CORA - Stage 14 Overlap Voter  |  Testbench
//  File    : overlap_voter_tb.v
//  Target  : Icarus Verilog 12 (iverilog / vvp)
//  Simulates ZCU104 timing: 200 MHz clock (5 ns period)
// =============================================================================
//  TEST SUITE
//  ──────────────────────────────────────────────────────────────────────
//  T01  Basic pair - class 3 wins by score sum
//  T02  Class at boundary (class 9) reinforced in second window
//  T03  Tie-break - lowest index wins (class 0)
//  T04  All-zero both windows - class 0, score 0
//  T05  Negative scores - least-negative class wins
//  T06  voter_busy assertion / de-assertion
//  T07  pred_valid de-asserts next cycle after firing
//  T08  pred_valid does NOT fire on first window alone
//  T09  Reset mid-hold clears state; next pair works cleanly
//  T10  Three consecutive pairs - alternating winners
//  T11  Sliding-window mode - every window after first produces a decision
//  T12  Score overflow guard - max Q8.8 + max Q8.8 = max Q9.8, no wrap
//  T13  Reset-to-first-window latency = 0 extra cycles
//  T14  Back-to-back score_valid pulses with no gap (stress)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module overlap_voter_tb;

// ─── Parameters ──────────────────────────────────────────────────────────────
localparam NUM_CLASSES = 10;
localparam SCORE_WIDTH = 16;
localparam SUM_WIDTH   = 17;
localparam CLASS_BITS  = 4;
localparam CLK_PERIOD  = 5;    // 200 MHz  (5 ns) - ZCU104 target

// ─── DUT signals ─────────────────────────────────────────────────────────────
reg                              clk, rst_n, score_valid;
reg  [NUM_CLASSES*SCORE_WIDTH-1:0] score_in;

wire [CLASS_BITS-1:0]            pred_class;
wire [SUM_WIDTH-1:0]             pred_score;
wire                             pred_valid;
wire                             voter_busy;

// Sliding-window DUT (separate instance for T11)
reg                              sv_score_valid;
reg  [NUM_CLASSES*SCORE_WIDTH-1:0] sv_score_in;
wire [CLASS_BITS-1:0]            sv_pred_class;
wire [SUM_WIDTH-1:0]             sv_pred_score;
wire                             sv_pred_valid;
wire                             sv_voter_busy;

// ─── DUT instantiation (paired mode) ─────────────────────────────────────────
overlap_voter #(
    .NUM_CLASSES(NUM_CLASSES),
    .SCORE_WIDTH(SCORE_WIDTH),
    .SLIDING_WINDOW(0)
) dut (
    .clk(clk), .rst_n(rst_n),
    .score_in(score_in), .score_valid(score_valid),
    .pred_class(pred_class), .pred_score(pred_score),
    .pred_valid(pred_valid), .voter_busy(voter_busy)
);

// ─── DUT instantiation (sliding-window mode for T11) ─────────────────────────
overlap_voter #(
    .NUM_CLASSES(NUM_CLASSES),
    .SCORE_WIDTH(SCORE_WIDTH),
    .SLIDING_WINDOW(1)
) dut_sw (
    .clk(clk), .rst_n(rst_n),
    .score_in(sv_score_in), .score_valid(sv_score_valid),
    .pred_class(sv_pred_class), .pred_score(sv_pred_score),
    .pred_valid(sv_pred_valid), .voter_busy(sv_voter_busy)
);

// ─── Clock ───────────────────────────────────────────────────────────────────
always #(CLK_PERIOD/2) clk = ~clk;

// ─── Scoreboard ──────────────────────────────────────────────────────────────
integer pass_cnt = 0;
integer fail_cnt = 0;
integer test_num = 0;

task PASS;
    input [255:0] msg;
    begin
        $display("  [PASS] T%02d: %s", test_num, msg);
        pass_cnt = pass_cnt + 1;
    end
endtask

task FAIL;
    input [511:0] msg;
    begin
        $display("  [FAIL] T%02d: %s", test_num, msg);
        fail_cnt = fail_cnt + 1;
    end
endtask

// ─── Helpers ─────────────────────────────────────────────────────────────────

// Pack 10 signed 16-bit values into flat bus
function [NUM_CLASSES*SCORE_WIDTH-1:0] pack10;
    input signed [15:0] s0,s1,s2,s3,s4,s5,s6,s7,s8,s9;
    begin
        pack10 = {s9,s8,s7,s6,s5,s4,s3,s2,s1,s0};
    end
endfunction

// Send one score_valid pulse (main DUT)
task send_win;
    input signed [15:0] s0,s1,s2,s3,s4,s5,s6,s7,s8,s9;
    begin
        score_in    = pack10(s0,s1,s2,s3,s4,s5,s6,s7,s8,s9);
        score_valid = 1'b1;
        @(posedge clk); #1;
        score_valid = 1'b0;
    end
endtask

// Send one score_valid pulse (sliding-window DUT)
task sv_send_win;
    input signed [15:0] s0,s1,s2,s3,s4,s5,s6,s7,s8,s9;
    begin
        sv_score_in    = pack10(s0,s1,s2,s3,s4,s5,s6,s7,s8,s9);
        sv_score_valid = 1'b1;
        @(posedge clk); #1;
        sv_score_valid = 1'b0;
    end
endtask

// Wait N cycles
task wait_cycles;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i+1) @(posedge clk);
        #1;
    end
endtask

// Assert pred_valid fired THIS cycle and check class/score
task check_decision;
    input [CLASS_BITS-1:0]  exp_class;
    input [SUM_WIDTH-1:0]   exp_score;
    input [255:0]           desc;
    begin
        if (!pred_valid)
            FAIL({desc, " - pred_valid not asserted"});
        else if (pred_class !== exp_class) begin
            $display("    got class=%0d, expected=%0d", pred_class, exp_class);
            FAIL({desc, " - wrong pred_class"});
        end else if (pred_score !== exp_score) begin
            $display("    got score=%0d, expected=%0d", pred_score, exp_score);
            FAIL({desc, " - wrong pred_score"});
        end else
            PASS(desc);
    end
endtask

// Assert pred_valid NOT asserted
task check_no_decision;
    input [255:0] desc;
    begin
        if (pred_valid)
            FAIL({desc, " - pred_valid should NOT be asserted"});
        else
            PASS(desc);
    end
endtask

// ─── VCD waveform dump ───────────────────────────────────────────────────────
initial begin
    $dumpfile("overlap_voter_sim.vcd");
    $dumpvars(0, overlap_voter_tb);
end

// ─── Main stimulus ───────────────────────────────────────────────────────────
initial begin
    // Init
    clk = 0; rst_n = 0;
    score_in = 0; score_valid = 0;
    sv_score_in = 0; sv_score_valid = 0;

    $display("==================================================");
    $display("  CORA Stage 14 - Overlap Voter Simulation");
    $display("  Target: ZCU104 (XCZU7EV)  Clock: 200 MHz (5ns)");
    $display("==================================================");

    // Release reset
    repeat(4) @(posedge clk); #1;
    rst_n = 1;
    @(posedge clk); #1;

    // ──────────────────────────────────────────────────────────────────
    //  T01  Basic pair - class 3 wins by summed scores
    // ──────────────────────────────────────────────────────────────────
    test_num = 1;
    $display("\n[T01] Basic pair - class 3 wins");
    // Win N:  class3=300, others low
    send_win(10, 20, 15, 300, 5, 8, 12, 3, 7, 9);
    // Win N+1: class3=200, class7=180  → sum class3=500, class7=183
    send_win(5, 10, 8, 200, 3, 4, 6, 180, 2, 1);
    // pred_valid fires on the cycle AFTER the second send_win posedge
    // (send_win samples on posedge then adds #1; we're 1ns past that posedge)
    check_decision(4'd3, 17'd500, "class3 wins (300+200=500)");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T02  Boundary reinforcement - class 9 wins across two windows
    // ──────────────────────────────────────────────────────────────────
    test_num = 2;
    $display("\n[T02] Boundary reinforcement - class 9");
    send_win(100,100,100,100,100,100,100,100,100, 150); // class9=150
    send_win( 50, 50, 50, 50, 50, 50, 50, 50, 50, 200); // class9=200 → sum=350; others max=150
    check_decision(4'd9, 17'd350, "class9 wins (150+200=350)");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T03  Tie-break - all equal, class 0 wins (lowest index in tree)
    // ──────────────────────────────────────────────────────────────────
    test_num = 3;
    $display("\n[T03] Tie-break - class 0 wins");
    send_win(100,100,100,100,100,100,100,100,100,100);
    send_win(100,100,100,100,100,100,100,100,100,100);
    check_decision(4'd0, 17'd200, "class0 wins tie (all sum=200)");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T04  All-zero both windows
    // ──────────────────────────────────────────────────────────────────
    test_num = 4;
    $display("\n[T04] All-zero");
    send_win(0,0,0,0,0,0,0,0,0,0);
    send_win(0,0,0,0,0,0,0,0,0,0);
    check_decision(4'd0, 17'd0, "all-zero: class0, score=0");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T05  Negative scores - least negative wins
    //       All Q8.8 negative; class 5 is -10, others are -100
    // ──────────────────────────────────────────────────────────────────
    test_num = 5;
    $display("\n[T05] Negative scores - class 5 least negative");
    send_win(-100,-100,-100,-100,-100, -10,-100,-100,-100,-100);
    send_win(-100,-100,-100,-100,-100,  -5,-100,-100,-100,-100);
    // sum class5 = -15, all others = -200
    // -15 in 17-bit two's complement = 17'h1FFF1 = 131057
    check_decision(4'd5, 17'h1FFF1, "class5 wins (-10+(-5)=-15 > -200)");
    // -15 in 17-bit signed = 17'h1_FFF1 = 17'b1_1111_1111_1111_0001
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T06  voter_busy: high between windows, low after decision
    // ──────────────────────────────────────────────────────────────────
    test_num = 6;
    $display("\n[T06] voter_busy assertion");
    send_win(1,2,3,4,5,6,7,8,9,10);   // sends Window N
    if (voter_busy !== 1'b1) FAIL("voter_busy not high after Window N");
    else                     PASS("voter_busy=1 after Window N");
    send_win(1,2,3,4,5,6,7,8,9,10);   // sends Window N+1
    // After decision: voter_busy should de-assert  (check next cycle)
    @(posedge clk); #1;
    if (voter_busy !== 1'b0) FAIL("voter_busy still high after decision");
    else                     PASS("voter_busy=0 after decision");
    wait_cycles(2);

    // ──────────────────────────────────────────────────────────────────
    //  T07  pred_valid de-asserts the cycle AFTER it fires
    // ──────────────────────────────────────────────────────────────────
    test_num = 7;
    $display("\n[T07] pred_valid is a 1-cycle pulse only");
    send_win(50,60,70,80,10,20,30,40,5,15);
    send_win(50,60,70,80,10,20,30,40,5,15); // pred_valid fires here
    // sample one cycle later - should be 0
    @(posedge clk); #1;
    if (pred_valid !== 1'b0) FAIL("pred_valid still high after 1 cycle");
    else                     PASS("pred_valid de-asserted after 1 cycle");
    wait_cycles(2);

    // ──────────────────────────────────────────────────────────────────
    //  T08  pred_valid must NOT fire after only the first window
    // ──────────────────────────────────────────────────────────────────
    test_num = 8;
    $display("\n[T08] pred_valid silent after Window N only");
    score_in    = pack10(10,20,30,40,50,60,70,80,90,100);
    score_valid = 1'b1;
    @(posedge clk); #1;
    score_valid = 1'b0;
    check_no_decision("no decision after single window");
    wait_cycles(1);
    // Now send the second window to drain the FSM
    send_win(0,0,0,0,0,0,0,0,0,0);
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T09  Reset mid-hold - clears score_N, next pair works correctly
    // ──────────────────────────────────────────────────────────────────
    test_num = 9;
    $display("\n[T09] Reset mid-hold");
    send_win(200,200,200,200,200,200,200,200,200,200); // Window N
    // Assert reset while in HOLD
    rst_n = 1'b0;
    repeat(2) @(posedge clk); #1;
    rst_n = 1'b1;
    @(posedge clk); #1;
    if (voter_busy !== 1'b0) FAIL("voter_busy not cleared by reset");
    else                     PASS("voter_busy cleared by reset");
    // Now send a fresh pair - class 1 wins
    send_win(10,500,10,10,10,10,10,10,10,10); // N
    send_win(10,300,10,10,10,10,10,10,10,10); // N+1
    check_decision(4'd1, 17'd800, "fresh pair after reset: class1 wins (500+300=800)");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T10  Three consecutive pairs - alternating winners
    // ──────────────────────────────────────────────────────────────────
    test_num = 10;
    $display("\n[T10] Three consecutive pairs");

    // Pair 1: class 2 wins
    send_win(5,5,400,5,5,5,5,5,5,5);
    send_win(5,5,300,5,5,5,5,5,5,5);
    check_decision(4'd2, 17'd700, "pair1: class2 wins (400+300=700)");
    wait_cycles(3);

    // Pair 2: class 7 wins
    send_win(10,10,10,10,10,10,10,600,10,10);
    send_win(10,10,10,10,10,10,10,100,10,10);
    check_decision(4'd7, 17'd700, "pair2: class7 wins (600+100=700)");
    wait_cycles(3);

    // Pair 3: class 0 wins
    send_win(999,5,5,5,5,5,5,5,5,5);
    send_win(500,5,5,5,5,5,5,5,5,5);
    // 999+500=1499; max Q9.8 signed = 32767 - no overflow
    check_decision(4'd0, 17'd1499, "pair3: class0 wins (999+500=1499)");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T11  Sliding-window mode - uses dut_sw instance
    // ──────────────────────────────────────────────────────────────────
    test_num = 11;
    $display("\n[T11] Sliding-window mode (every consecutive pair)");
    // Win 0: class 4 = 100
    sv_send_win(0,0,0,0,100,0,0,0,0,0);
    if (sv_pred_valid) FAIL("sliding: pred_valid on first window only");
    else               PASS("sliding: no decision after win0");

    // Win 1: class 6 = 200 → sum: class4=100+0=100, class6=0+200=200 → class6 wins
    sv_send_win(0,0,0,0,0,0,200,0,0,0);
    if (!sv_pred_valid)     FAIL("sliding: pred_valid not fired after win1");
    else if (sv_pred_class != 4'd6) begin
        $display("    got=%0d exp=6", sv_pred_class);
        FAIL("sliding: wrong class (win0+win1)");
    end else               PASS("sliding: class6 wins (win0+win1)");

    // Win 2: class 6 = 300 → win1+win2: class6=200+300=500 → class6 wins again
    sv_send_win(0,0,0,0,0,0,300,0,0,0);
    if (!sv_pred_valid)    FAIL("sliding: pred_valid not fired after win2");
    else if (sv_pred_class != 4'd6) FAIL("sliding: wrong class (win1+win2)");
    else                   PASS("sliding: class6 wins (win1+win2)");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T12  Max-value overflow guard (Q8.8 max signed = 32767)
    //       32767 + 32767 = 65534, fits in 17-bit signed (max = 65535)
    // ──────────────────────────────────────────────────────────────────
    test_num = 12;
    $display("\n[T12] Max-value overflow guard");
    send_win(16'h7FFF,0,0,0,0,0,0,0,0,0); // class0 = 32767
    send_win(16'h7FFF,0,0,0,0,0,0,0,0,0); // class0 = 32767
    // Expected sum = 65534 = 17'h0FFFE = 17'd65534
    check_decision(4'd0, 17'd65534, "max Q8.8+Q8.8=65534 no overflow");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T13  Reset-to-first-decision latency: exactly 2 score_valid pulses
    // ──────────────────────────────────────────────────────────────────
    test_num = 13;
    $display("\n[T13] Latency = exactly 2 score_valid pulses from reset");
    rst_n = 1'b0; repeat(3) @(posedge clk); #1; rst_n = 1'b1; @(posedge clk); #1;
    send_win(0,0,0,0,0,0,0,0,0, 50);
    send_win(0,0,0,0,0,0,0,0,0,100);
    if (!pred_valid) FAIL("decision did not arrive after exactly 2 windows");
    else             PASS("decision arrives on 2nd score_valid (latency OK)");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  T14  Back-to-back score_valid (no idle gap between pairs)
    // ──────────────────────────────────────────────────────────────────
    test_num = 14;
    $display("\n[T14] Back-to-back pairs (stress: no gaps between windows)");
    // Pair A: class 8 wins
    score_in = pack10(0,0,0,0,0,0,0,0,400,0);
    score_valid = 1'b1; @(posedge clk); #1;
    score_in = pack10(0,0,0,0,0,0,0,0,200,0);
    // N+1 sent immediately (no gap)
    @(posedge clk); #1;
    score_valid = 1'b0;
    if (!pred_valid)           FAIL("stress pair A: no decision");
    else if (pred_class != 4'd8) FAIL("stress pair A: wrong class");
    else                       PASS("stress pair A: class8 wins (400+200=600)");

    // Pair B immediately after pair A (no gap: score_valid was cleared above)
    score_in = pack10(0,0,0,0,0,300,0,0,0,0);
    score_valid = 1'b1; @(posedge clk); #1;
    score_in = pack10(0,0,0,0,0,150,0,0,0,0);
    @(posedge clk); #1;
    score_valid = 1'b0;
    if (!pred_valid)           FAIL("stress pair B: no decision");
    else if (pred_class != 4'd5) FAIL("stress pair B: wrong class");
    else                       PASS("stress pair B: class5 wins (300+150=450)");
    wait_cycles(3);

    // ──────────────────────────────────────────────────────────────────
    //  Final summary
    // ──────────────────────────────────────────────────────────────────
    $display("\n==================================================");
    $display("  SIMULATION COMPLETE");
    $display("  Tests run : %0d", pass_cnt + fail_cnt);
    $display("  Passed    : %0d", pass_cnt);
    $display("  Failed    : %0d", fail_cnt);
    if (fail_cnt == 0)
        $display("  *** ALL TESTS PASSED - ZCU104 READY ***");
    else
        $display("  *** FAILURES DETECTED - REVIEW ABOVE ***");
    $display("==================================================");
    $finish;
end

// ─── Timeout watchdog (prevents infinite hang) ───────────────────────────────
initial begin
    #500000;  // 500 µs simulation limit
    $display("[WATCHDOG] Simulation exceeded time limit - forcing exit");
    $finish;
end

endmodule
`default_nettype wire
