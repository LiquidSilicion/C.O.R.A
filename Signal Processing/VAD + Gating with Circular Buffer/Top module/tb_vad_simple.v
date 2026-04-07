`timescale 1ns / 1ps

module tb_vad_simple;
    // ─────────────────────────────────────────────────────────────────────
    // Signals
    // ─────────────────────────────────────────────────────────────────────
    reg         clk, rst_n;
    reg  [15:0] audio_in;
    reg         sample_valid;

    wire [15:0] audio_out;
    wire        audio_valid;
    wire        speech_valid;

    // ─────────────────────────────────────────────────────────────────────
    // DUT Instantiation
    // ─────────────────────────────────────────────────────────────────────
    vad_circ_buffer_top #(
        .THRESHOLD_ON        (32'd150000),
        .THRESHOLD_OFF       (32'd50000),
        .HANGOVER_MS         (50),
        .WINDOW_MS           (5),
        .PRE_TRIGGER_SAMPLES (3200),
        .BUFFER_SIZE         (24000)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .audio_in         (audio_in),
        .sample_valid     (sample_valid),
        .audio_out        (audio_out),
        .audio_valid      (audio_valid),
        .speech_valid     (speech_valid),
        .smoothed_energy  (),
        .noise_floor      (),
        .zero_cross_rate  ()
    );

    // ─────────────────────────────────────────────────────────────────────
    // 100MHz Clock
    // ─────────────────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ─────────────────────────────────────────────────────────────────────
    // 16kHz Sample Valid Generator
    // ─────────────────────────────────────────────────────────────────────
    reg [12:0] clk_div;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div      <= 13'd0;
            sample_valid <= 1'b0;
        end else if (clk_div == 13'd6249) begin
            sample_valid <= 1'b1;
            clk_div      <= 13'd0;
        end else begin
            sample_valid <= 1'b0;
            clk_div      <= clk_div + 1'b1;
        end
    end

    // ─────────────────────────────────────────────────────────────────────
    // Test Sequence
    // ─────────────────────────────────────────────────────────────────────
    reg test_pass;

    initial begin
        test_pass = 1'b1;
        rst_n     = 1'b0;
        audio_in  = 16'd0;

        $display("========================================");
        $display("  Simple VAD + Circular Buffer Test");
        $display("========================================");

        #100 rst_n = 1'b1;
        $display("[%0t] Reset released.", $time);

        // PHASE 1: Silence (let noise floor adapt to ~0)
        $display("[%0t] Phase 1: Silence (adapting noise floor)...", $time);
        inject_silence(2000);

        // PHASE 2: Speech-like signal (should trigger VAD)
        $display("[%0t] Phase 2: Injecting speech...", $time);
        inject_speech(5000, 16'd2000);

        // Verify trigger happened
        if (speech_valid)
            $display("[PASS] speech_valid asserted during speech phase.");
        else begin
            $display("[FAIL] speech_valid never asserted. VAD did not trigger.");
            test_pass = 1'b0;
        end

        // PHASE 3: Silence (should enter hangover then return to IDLE)
        $display("[%0t] Phase 3: Silence (testing hangover)...", $time);
        inject_silence(1500);

        // Verify system returned to idle
        #50;
        if (!speech_valid)
            $display("[PASS] speech_valid deasserted after hangover.");
        else begin
            $display("[FAIL] speech_valid stuck high after silence.");
            test_pass = 1'b0;
        end

        // Final result
        $display("========================================");
        if (test_pass)
            $display("  RESULT: ALL CHECKS PASSED");
        else
            $display("  RESULT: TEST FAILED");
        $display("========================================");

        #100 $finish;
    end

    // ─────────────────────────────────────────────────────────────────────
    // Stimulus Tasks
    // ─────────────────────────────────────────────────────────────────────
    task inject_silence;
        input [31:0] num_samples;
        integer i;
        begin
            for (i = 0; i < num_samples; i = i + 1) begin
                @(posedge clk);
                if (sample_valid) audio_in <= 16'd0;
            end
        end
    endtask

    task inject_speech;
        input [31:0] num_samples;
        input [15:0] amplitude;
        integer i;
        reg [1:0]  hold_cnt;
        reg [15:0] curr_val;
        begin
            curr_val = amplitude;
            hold_cnt = 2'd0;
            for (i = 0; i < num_samples; i = i + 1) begin
                @(posedge clk);
                if (sample_valid) begin
                    // Hold polarity for 4 samples -> ~20 zero-crossings per 80-sample window
                    if (hold_cnt == 2'd3) begin
                        curr_val = (curr_val > 0) ? ~amplitude + 1'b1 : amplitude;
                        hold_cnt = 2'd0;
                    end else begin
                        hold_cnt = hold_cnt + 1'b1;
                    end
                    audio_in <= curr_val;
                end
            end
        end
    endtask

    // ─────────────────────────────────────────────────────────────────────
    // Simple Monitor (prints when speech_valid changes state)
    // ─────────────────────────────────────────────────────────────────────
    reg speech_prev;
    always @(posedge clk) begin
        if (!rst_n) speech_prev <= 1'b0;
        else begin
            speech_prev <= speech_valid;
            if (speech_valid && !speech_prev)
                $display("[%0t] >>> speech_valid went HIGH (trigger detected)", $time);
            if (!speech_valid && speech_prev)
                $display("[%0t] <<< speech_valid went LOW (hangover ended)", $time);
        end
    end

endmodule
