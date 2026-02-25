module tb_vad;

    // --------------------------------------------------------
    // Parameters matching DUT
    // --------------------------------------------------------
    localparam SAMPLE_RATE        = 16000;
    localparam CLK_FREQ           = 100_000_000;
    localparam SAMPLES_PER_WINDOW = 160;         // 10ms @ 16kHz
    localparam HANGOVER_SAMPLES   = 4800;        // 300ms
    localparam ZCR_MIN            = 15;
    localparam ZCR_MAX            = 45;

    // Clock: 100MHz → 10ns period
    localparam CLK_PERIOD   = 10;
    // Sample valid every 6250 clocks (100MHz / 16kHz)
    localparam SAMPLE_TICKS = 6250;

    // --------------------------------------------------------
    // DUT ports
    // --------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg [15:0] audio_in;
    reg        sample_valid;

    wire       speech_detected;
    wire       vad_raw;
    wire       pre_trigger_pulse;
    wire       recording_active;
    wire [31:0] smoothed_energy;
    wire [31:0] noise_floor;
    wire [15:0] zero_cross_rate;

    // --------------------------------------------------------
    // DUT instantiation
    // --------------------------------------------------------
    vad #(
        .SAMPLE_RATE       (SAMPLE_RATE),
        .CLK_FREQ          (CLK_FREQ),
        .THRESHOLD_OFF     (32'd1_000_000),
        .THRESHOLD_ADAPT_RATE(4),
        .ZCR_MIN_SPEECH    (ZCR_MIN),
        .ZCR_MAX_SPEECH    (ZCR_MAX),
        .HANGOVER_MS       (300),
        .WINDOW_MS         (10)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .audio_in          (audio_in),
        .sample_valid      (sample_valid),
        .speech_detected   (speech_detected),
        .vad_raw           (vad_raw),
        .pre_trigger_pulse (pre_trigger_pulse),
        .recording_active  (recording_active),
        .smoothed_energy   (smoothed_energy),
        .noise_floor       (noise_floor),
        .zero_cross_rate   (zero_cross_rate)
    );

    // --------------------------------------------------------
    // Clock generator
    // --------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --------------------------------------------------------
    // Counters / tracking
    // --------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;
    integer pre_trig_count = 0;  // count pre_trigger_pulse edges

    // Track pre_trigger_pulse count
    always @(posedge clk) begin
        if (pre_trigger_pulse)
            pre_trig_count <= pre_trig_count + 1;
    end

    // --------------------------------------------------------
    // Task: send N samples with given PCM value
    // --------------------------------------------------------
    task send_samples;
        input integer n_samples;
        input [15:0] sample_val;
        integer i;
        begin
            for (i = 0; i < n_samples; i = i + 1) begin
                @(posedge clk);
                audio_in     = sample_val;
                sample_valid = 1'b1;
                @(posedge clk);
                sample_valid = 1'b0;
                // wait remaining ticks to simulate 16kHz spacing
                repeat(SAMPLE_TICKS - 2) @(posedge clk);
            end
        end
    endtask

    // --------------------------------------------------------
    // Task: send speech-like signal (alternating + and - to hit ZCR range)
    // Creates ~30 ZCR per 160 samples (within 15-45 range)
    // Amplitude 8000 (high energy, well above noise floor)
    // --------------------------------------------------------
    task send_speech_samples;
        input integer n_samples;
        integer i;
        reg [15:0] val;
        begin
            for (i = 0; i < n_samples; i = i + 1) begin
                // Alternate polarity every ~5 samples → ~32 ZCR per 160 samples
                if ((i / 5) % 2 == 0)
                    val = 16'h1F40;   //  +8000
                else
                    val = 16'hE0C0;   //  -8000 (two's complement)
                @(posedge clk);
                audio_in     = val;
                sample_valid = 1'b1;
                @(posedge clk);
                sample_valid = 1'b0;
                repeat(SAMPLE_TICKS - 2) @(posedge clk);
            end
        end
    endtask

    // --------------------------------------------------------
    // Task: send noise burst (high energy but ZCR too high - out of speech range)
    // Creates ~90 ZCR per 160 samples (above ZCR_MAX=45 → not speech)
    // --------------------------------------------------------
    task send_noise_samples;
        input integer n_samples;
        integer i;
        reg [15:0] val;
        begin
            for (i = 0; i < n_samples; i = i + 1) begin
                // Alternate every sample → 160 ZCR per window (well above 45)
                if (i % 2 == 0)
                    val = 16'h1F40;   //  +8000
                else
                    val = 16'hE0C0;   //  -8000
                @(posedge clk);
                audio_in     = val;
                sample_valid = 1'b1;
                @(posedge clk);
                sample_valid = 1'b0;
                repeat(SAMPLE_TICKS - 2) @(posedge clk);
            end
        end
    endtask

    // --------------------------------------------------------
    // Task: check assertion with label
    // --------------------------------------------------------
    task check;
        input [127:0] test_name;
        input         actual;
        input         expected;
        begin
            if (actual === expected) begin
                $display("  PASS  [%0s]  got %b", test_name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  [%0s]  expected %b  got %b  @time %0t",
                         test_name, expected, actual, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // --------------------------------------------------------
    // MAIN TEST
    // --------------------------------------------------------
    initial begin
        $dumpfile("tb_vad.vcd");
        $dumpvars(0, tb_vad);

        // --- Reset ---
        $display("\n=== VAD TESTBENCH ===\n");
        rst_n        = 1'b0;
        audio_in     = 16'd0;
        sample_valid = 1'b0;
        repeat(20) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ======================================================
        // TB1: Silence - 5 windows of zeros
        //      Expect: speech_detected = 0, vad_raw = 0
        // ======================================================
        $display("--- TB1: Silence (5 windows, 800 samples) ---");
        send_samples(800, 16'd0);
        @(posedge clk);
        check("TB1 speech_detected=0", speech_detected, 1'b0);
        check("TB1 vad_raw=0",         vad_raw,         1'b0);
        check("TB1 pre_trig=0",        pre_trigger_pulse, 1'b0);

        // ======================================================
        // TB2: Speech - 20 windows (200ms) of speech-like signal
        //      Expect: speech_detected goes HIGH within a few windows
        //              vad_raw HIGH
        //              pre_trigger_pulse fires exactly once
        // ======================================================
        $display("\n--- TB2: Speech signal (20 windows = 200ms) ---");
        pre_trig_count = 0;   // reset counter for this test
        send_speech_samples(20 * SAMPLES_PER_WINDOW);
        @(posedge clk);

        $display("  INFO  smoothed_energy = %0d", smoothed_energy);
        $display("  INFO  noise_floor     = %0d", noise_floor);
        $display("  INFO  zero_cross_rate = %0d", zero_cross_rate);

        check("TB2 speech_detected=1", speech_detected,    1'b1);
        check("TB2 vad_raw=1",         vad_raw,            1'b1);
        check("TB2 recording=1",       recording_active,   1'b1);

        // pre_trigger_pulse should have fired exactly once
        if (pre_trig_count == 1)
            $display("  PASS  [TB2 pre_trigger one-shot]  fired %0d time(s)", pre_trig_count);
        else
            $display("  FAIL  [TB2 pre_trigger one-shot]  fired %0d time(s) (expected 1)", pre_trig_count);

        // ======================================================
        // TB3: Hangover - stop speech, check held for ~300ms
        //      Send silence: speech_detected should stay HIGH
        //      for HANGOVER_SAMPLES more samples
        // ======================================================
        $display("\n--- TB3: Hangover (silence after speech) ---");
        // Send 10 windows of silence - should still be in hangover
        send_samples(10 * SAMPLES_PER_WINDOW, 16'd0);
        @(posedge clk);
        check("TB3 hangover_active", speech_detected, 1'b1);

        // Now drain the rest of hangover: 4800 - 1600 = 3200 more silence samples
        send_samples(3200, 16'd0);
        // Wait extra cycles for hangover to expire
        repeat(50) @(posedge clk);
        check("TB3 hangover_expired", speech_detected, 1'b0);

        // ======================================================
        // TB4: Noise burst (high energy, ZCR out of range)
        //      Expect: speech_detected = 0 (ZCR gate blocks it)
        // ======================================================
        $display("\n--- TB4: Noise burst (wrong ZCR - should not fire) ---");
        // Let system settle to silence
        send_samples(20 * SAMPLES_PER_WINDOW, 16'd0);
        repeat(100) @(posedge clk);

        // Now send noise (alternates every sample - ZCR >> 45)
        send_noise_samples(20 * SAMPLES_PER_WINDOW);
        @(posedge clk);
        $display("  INFO  ZCR during noise = %0d (should be > 45)", zero_cross_rate);
        // energy_vad will be 1 but zcr_vad should be 0 → vad_raw = 0
        check("TB4 vad_raw=0 (ZCR too high)", vad_raw, 1'b0);
        check("TB4 speech_detected=0",         speech_detected, 1'b0);

        // ======================================================
        // TB5: Verify pre_trigger_pulse is one-shot
        //      Start new speech burst, count pulses over 5 windows
        // ======================================================
        $display("\n--- TB5: pre_trigger_pulse one-shot verify ---");
        // Reset to silence first
        send_samples(10 * SAMPLES_PER_WINDOW, 16'd0);
        repeat(5000) @(posedge clk);  // wait hangover clear

        pre_trig_count = 0;
        send_speech_samples(5 * SAMPLES_PER_WINDOW);  // 5 windows of speech
        repeat(100) @(posedge clk);

        if (pre_trig_count == 1)
            $display("  PASS  [TB5 one-shot] pre_trigger_pulse fired exactly once (%0d)", pre_trig_count);
        else if (pre_trig_count == 0)
            $display("  FAIL  [TB5 one-shot] pre_trigger_pulse never fired (VAD may not have triggered)");
        else
            $display("  FAIL  [TB5 one-shot] pre_trigger_pulse fired %0d times (expected 1)", pre_trig_count);

        // ======================================================
        // Summary
        // ======================================================
        $display("\n=== RESULTS: %0d PASS / %0d FAIL ===\n", pass_count, fail_count);

        if (fail_count == 0)
            $display("All tests passed.\n");
        else
            $display("FAILURES detected - review above.\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #500_000_000; // 500ms simulation time limit
        $display("TIMEOUT - simulation exceeded 500ms wall time");
        $finish;
    end

endmodule
