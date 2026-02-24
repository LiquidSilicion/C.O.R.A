`timescale 1ns / 1ps

module tb_vad();

    // Parameters
    localparam SAMPLE_RATE = 16000;
    localparam CLK_FREQ = 100000000;
    localparam CLK_PERIOD = 10; // 100MHz = 10ns
    
    // Calculated parameters from DUT
    localparam SAMPLES_PER_WINDOW = SAMPLE_RATE * 10 / 1000; // 160 samples for 10ms @16kHz
    localparam HANGOVER_SAMPLES = SAMPLE_RATE * 300 / 1000;  // 4800 samples
    localparam PRE_TRIGGER_SAMPLES = SAMPLE_RATE * 200 / 1000; // 3200 samples
    
    // Testbench signals
    reg clk;
    reg rst_n;
    reg [15:0] audio_in;
    reg sample_valid;
    wire speech_detected;
    wire vad_raw;
    wire recording_active;
    wire pre_trigger_active;
    wire [31:0] smoothed_energy;
    wire [31:0] noise_floor;
    wire [15:0] zero_cross_rate;
    
    // Test control
    integer test_case = 0;
    integer errors = 0;
    integer window_count = 0;
    integer sample_count = 0;
    integer i, j, k;
    
    // Expected values
    reg [31:0] expected_noise_floor;
    reg [31:0] expected_smoothed_energy;
    reg [15:0] expected_zcr;
    reg expected_vad;
    
    // File handling for test vectors (optional)
    integer file_id;
    integer scan_file;
    reg [15:0] test_sample;
    
    // Instantiate VAD module
    vad #(
        .SAMPLE_RATE(SAMPLE_RATE),
        .CLK_FREQ(CLK_FREQ),
        .THRESHOLD_ON(32'd2000000),
        .THRESHOLD_OFF(32'd1000000),
        .THRESHOLD_ADAPT_RATE(4),
        .ZCR_MIN_SPEECH(15),
        .ZCR_MAX_SPEECH(45),
        .HANGOVER_MS(300),
        .PRE_TRIGGER_MS(200),
        .WINDOW_MS(10)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .audio_in(audio_in),
        .sample_valid(sample_valid),
        .speech_detected(speech_detected),
        .vad_raw(vad_raw),
        .recording_active(recording_active),
        .pre_trigger_active(pre_trigger_active),
        .smoothed_energy(smoothed_energy),
        .noise_floor(noise_floor),
        .zero_cross_rate(zero_cross_rate)
    );
    
    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Main test sequence
    initial begin
        // Initialize
        clk = 0;
        rst_n = 0;
        audio_in = 16'd0;
        sample_valid = 0;
        
        // Print test header
        print_header();
        
        // Apply reset
        #(CLK_PERIOD*10);
        rst_n = 1;
        #(CLK_PERIOD*10);
        
        // Run test cases
        test_reset_state();                 // Test 1
        test_noise_floor_estimation();      // Test 2
        test_speech_detection_energy();     // Test 3
        test_zero_crossing();                // Test 4
        test_hangover();                     // Test 5
        test_pre_trigger();                  // Test 6
        test_noise_adaptation();             // Test 7
        test_edge_cases();                   // Test 8
        test_burst_detection();              // Test 9
        test_continuous_operation();         // Test 10
        
        // Print summary
        print_summary();
        
        #(CLK_PERIOD*100);
        $finish;
    end
    
    // Task: Test 1 - Reset state verification
    task test_reset_state();
        begin
            test_case = 1;
            $display("\n[Test %0d] Reset State Verification", test_case);
            $display("----------------------------------------");
            
            // Apply reset
            @(negedge clk);
            rst_n = 0;
            #(CLK_PERIOD*5);
            
            // Check outputs during reset
            @(posedge clk);
            check_reset_outputs();
            
            // Release reset
            @(negedge clk);
            rst_n = 1;
            #(CLK_PERIOD*5);
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 2 - Noise floor estimation during silence
    task test_noise_floor_estimation();
        begin
            test_case = 2;
            $display("\n[Test %0d] Noise Floor Estimation", test_case);
            $display("----------------------------------------");
            
            // Generate silence (low amplitude noise)
            for (i = 0; i < SAMPLES_PER_WINDOW * 10; i = i + 1) begin
                @(posedge clk);
                audio_in <= $random % 100; // Low amplitude
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                // Check noise floor periodically
                if (i % SAMPLES_PER_WINDOW == 0 && i > 0) begin
                    $display("  Window %0d: Noise Floor = %0d", 
                            i/SAMPLES_PER_WINDOW, noise_floor);
                end
            end
            
            // Verify noise floor is within expected range
            if (noise_floor < 100 || noise_floor > 10000) begin
                $display("  ERROR: Noise floor %0d outside expected range", noise_floor);
                errors = errors + 1;
            end else begin
                $display("  PASS: Noise floor = %0d", noise_floor);
            end
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 3 - Speech detection based on energy
    task test_speech_detection_energy();
        begin
            test_case = 3;
            $display("\n[Test %0d] Speech Detection - Energy Threshold", test_case);
            $display("----------------------------------------");
            
            // First, establish noise floor with silence
            for (i = 0; i < SAMPLES_PER_WINDOW * 5; i = i + 1) begin
                @(posedge clk);
                audio_in <= $random % 50;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
            end
            
            $display("  Baseline noise floor: %0d", noise_floor);
            
            // Generate speech-like signal (high energy)
            $display("  Generating high energy signal...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 8; i = i + 1) begin
                @(posedge clk);
                audio_in <= 16'd5000 + ($random % 16'd5000);
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                // Check VAD state after each window
                if (i % SAMPLES_PER_WINDOW == 0 && i > 0) begin
                    window_count = i/SAMPLES_PER_WINDOW;
                    $display("  Window %0d: Energy=%0d, Noise=%0d, VAD=%0d", 
                            window_count, smoothed_energy, noise_floor, vad_raw);
                    
                    // Verify VAD triggers when energy > 4*noise
                    if (window_count > 2 && vad_raw !== 1'b1) begin
                        $display("  ERROR: VAD should be 1 for high energy signal");
                        errors = errors + 1;
                    end
                end
            end
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 4 - Zero crossing rate detection
    task test_zero_crossing();
        begin
            test_case = 4;
            $display("\n[Test %0d] Zero Crossing Rate Detection", test_case);
            $display("----------------------------------------");
            
            // Test low frequency (should have low ZCR)
            $display("  Testing low frequency signal...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 3; i = i + 1) begin
                @(posedge clk);
                audio_in <= (i % 100 < 10) ? 16'h7FFF : 16'h8000; // Low frequency
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                if (i % SAMPLES_PER_WINDOW == 0 && i > 0) begin
                    $display("    ZCR = %0d", zero_cross_rate);
                end
            end
            
            // Test medium frequency (should be in speech range)
            $display("  Testing medium frequency signal...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 3; i = i + 1) begin
                @(posedge clk);
                audio_in <= (i % 20 < 10) ? 16'h7FFF : 16'h8000; // Medium frequency
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                if (i % SAMPLES_PER_WINDOW == 0 && i > 0) begin
                    $display("    ZCR = %0d", zero_cross_rate);
                end
            end
            
            // Test high frequency (should have high ZCR)
            $display("  Testing high frequency signal...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 3; i = i + 1) begin
                @(posedge clk);
                audio_in <= (i % 4 < 2) ? 16'h7FFF : 16'h8000; // High frequency
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                if (i % SAMPLES_PER_WINDOW == 0 && i > 0) begin
                    $display("    ZCR = %0d", zero_cross_rate);
                end
            end
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 5 - Hangover mechanism
    task test_hangover();
        reg [15:0] hangover_count;
        begin
            test_case = 5;
            $display("\n[Test %0d] Hangover Mechanism", test_case);
            $display("----------------------------------------");
            
            // Generate speech burst
            $display("  Generating speech burst...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 2; i = i + 1) begin
                @(posedge clk);
                audio_in <= 16'd8000 + ($random % 16'd8000);
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
            end
            
            // Switch to silence and monitor hangover
            $display("  Monitoring hangover period (should last %0d samples)...", HANGOVER_SAMPLES);
            hangover_count = 0;
            
            for (i = 0; i < HANGOVER_SAMPLES + SAMPLES_PER_WINDOW; i = i + 1) begin
                @(posedge clk);
                audio_in <= $random % 50; // Silence
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                if (speech_detected) begin
                    hangover_count = hangover_count + 1;
                end
                
                // Check when hangover should end
                if (i == HANGOVER_SAMPLES - 1) begin
                    if (!speech_detected) begin
                        $display("  ERROR: Hangover ended too early at sample %0d", i);
                        errors = errors + 1;
                    end
                end
                
                if (i == HANGOVER_SAMPLES) begin
                    if (speech_detected) begin
                        $display("  ERROR: Hangover should have ended by sample %0d", i);
                        errors = errors + 1;
                    end else begin
                        $display("  PASS: Hangover correctly ended at sample %0d", i);
                    end
                end
            end
            
            $display("  Hangover duration: %0d samples", hangover_count);
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 6 - Pre-trigger mechanism
    task test_pre_trigger();
        begin
            test_case = 6;
            $display("\n[Test %0d] Pre-trigger Mechanism", test_case);
            $display("----------------------------------------");
            
            // Ensure we're in silence
            for (i = 0; i < SAMPLES_PER_WINDOW * 2; i = i + 1) begin
                @(posedge clk);
                audio_in <= $random % 50;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
            end
            
            $display("  Initial state: pre_trigger=%0d, recording=%0d", 
                    pre_trigger_active, recording_active);
            
            // Generate quick speech burst to trigger pre-trigger
            $display("  Generating trigger signal...");
            for (i = 0; i < 50; i = i + 1) begin
                @(posedge clk);
                audio_in <= 16'd10000;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
            end
            
            #(CLK_PERIOD * 10);
            
            if (!pre_trigger_active) begin
                $display("  ERROR: Pre-trigger should be active");
                errors = errors + 1;
            end else begin
                $display("  PASS: Pre-trigger activated");
            end
            
            // Monitor pre-trigger duration
            $display("  Monitoring pre-trigger duration...");
            for (i = 0; i < PRE_TRIGGER_SAMPLES + 100; i = i + 1) begin
                @(posedge clk);
                audio_in <= $random % 50;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                if (i == PRE_TRIGGER_SAMPLES - 10) begin
                    if (!pre_trigger_active) begin
                        $display("  ERROR: Pre-trigger ended too early");
                        errors = errors + 1;
                    end
                end
                
                if (i == PRE_TRIGGER_SAMPLES + 10) begin
                    if (pre_trigger_active) begin
                        $display("  ERROR: Pre-trigger should have ended");
                        errors = errors + 1;
                    end else begin
                        $display("  PASS: Pre-trigger correctly timed");
                    end
                end
            end
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 7 - Noise floor adaptation
    task test_noise_adaptation();
        reg [31:0] initial_noise;
        reg [31:0] final_noise;
        begin
            test_case = 7;
            $display("\n[Test %0d] Noise Floor Adaptation", test_case);
            $display("----------------------------------------");
            
            // Get initial noise floor
            initial_noise = noise_floor;
            $display("  Initial noise floor: %0d", initial_noise);
            
            // Gradually increase noise level
            $display("  Gradually increasing noise level...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 20; i = i + 1) begin
                @(posedge clk);
                // Ramp up noise amplitude
                audio_in <= (i * 10) % 2000;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                if (i % SAMPLES_PER_WINDOW == 0 && i > 0) begin
                    $display("    Window %0d: Noise floor = %0d", 
                            i/SAMPLES_PER_WINDOW, noise_floor);
                end
            end
            
            final_noise = noise_floor;
            $display("  Final noise floor: %0d", final_noise);
            
            // Verify noise floor increased
            if (final_noise <= initial_noise) begin
                $display("  ERROR: Noise floor did not adapt upward");
                errors = errors + 1;
            end else begin
                $display("  PASS: Noise floor adapted from %0d to %0d", 
                        initial_noise, final_noise);
            end
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 8 - Edge cases
    task test_edge_cases();
        begin
            test_case = 8;
            $display("\n[Test %0d] Edge Cases", test_case);
            $display("----------------------------------------");
            
            // Test zero input
            $display("  Testing zero input...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 2; i = i + 1) begin
                @(posedge clk);
                audio_in <= 16'd0;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
            end
            $display("    ZCR with zero input: %0d", zero_cross_rate);
            
            // Test maximum positive input
            $display("  Testing maximum positive input...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 2; i = i + 1) begin
                @(posedge clk);
                audio_in <= 16'h7FFF;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
            end
            $display("    Smoothed energy: %0d", smoothed_energy);
            
            // Test maximum negative input
            $display("  Testing maximum negative input...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 2; i = i + 1) begin
                @(posedge clk);
                audio_in <= 16'h8000;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
            end
            $display("    Smoothed energy: %0d", smoothed_energy);
            
            // Test alternating max/min
            $display("  Testing alternating max/min...");
            for (i = 0; i < SAMPLES_PER_WINDOW * 2; i = i + 1) begin
                @(posedge clk);
                audio_in <= (i % 2) ? 16'h7FFF : 16'h8000;
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
            end
            $display("    ZCR with alternating signal: %0d", zero_cross_rate);
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 9 - Burst detection
    task test_burst_detection();
        begin
            test_case = 9;
            $display("\n[Test %0d] Burst Detection", test_case);
            $display("----------------------------------------");
            
            for (j = 0; j < 5; j = j + 1) begin
                $display("  Burst %0d:", j);
                
                // Speech burst
                for (i = 0; i < SAMPLES_PER_WINDOW; i = i + 1) begin
                    @(posedge clk);
                    audio_in <= 16'd5000 + ($random % 16'd5000);
                    sample_valid <= 1;
                    #(CLK_PERIOD);
                    sample_valid <= 0;
                end
                
                #(CLK_PERIOD * 10);
                $display("    VAD after burst: %0d", vad_raw);
                
                // Silence
                for (i = 0; i < SAMPLES_PER_WINDOW * 2; i = i + 1) begin
                    @(posedge clk);
                    audio_in <= $random % 50;
                    sample_valid <= 1;
                    #(CLK_PERIOD);
                    sample_valid <= 0;
                end
                
                #(CLK_PERIOD * 10);
                $display("    VAD after silence: %0d", vad_raw);
            end
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Task: Test 10 - Continuous operation
    task test_continuous_operation();
        begin
            test_case = 10;
            $display("\n[Test %0d] Continuous Operation", test_case);
            $display("----------------------------------------");
            
            // Run a realistic mix of signals
            for (i = 0; i < SAMPLES_PER_WINDOW * 50; i = i + 1) begin
                @(posedge clk);
                
                // Generate varying signal types
                if (i < SAMPLES_PER_WINDOW * 10) begin
                    // Silence
                    audio_in <= $random % 100;
                end else if (i < SAMPLES_PER_WINDOW * 20) begin
                    // Speech-like
                    audio_in <= 16'd3000 + ($random % 16'd7000);
                end else if (i < SAMPLES_PER_WINDOW * 30) begin
                    // Noise
                    audio_in <= $random % 1000;
                end else if (i < SAMPLES_PER_WINDOW * 40) begin
                    // Speech-like
                    audio_in <= 16'd2000 + ($random % 16'd8000);
                end else begin
                    // Silence
                    audio_in <= $random % 100;
                end
                
                sample_valid <= 1;
                #(CLK_PERIOD);
                sample_valid <= 0;
                
                // Periodic status
                if (i % (SAMPLES_PER_WINDOW * 5) == 0 && i > 0) begin
                    $display("  Progress: %0d/%0d windows, speech=%0d, recording=%0d", 
                            i/SAMPLES_PER_WINDOW, 50, speech_detected, recording_active);
                end
            end
            
            $display("[Test %0d] Complete", test_case);
        end
    endtask
    
    // Helper task: Check reset outputs
    task check_reset_outputs();
        begin
            if (speech_detected !== 1'b0) begin
                $display("  ERROR: speech_detected should be 0 during reset");
                errors = errors + 1;
            end
            if (vad_raw !== 1'b0) begin
                $display("  ERROR: vad_raw should be 0 during reset");
                errors = errors + 1;
            end
            if (recording_active !== 1'b0) begin
                $display("  ERROR: recording_active should be 0 during reset");
                errors = errors + 1;
            end
            if (pre_trigger_active !== 1'b0) begin
                $display("  ERROR: pre_trigger_active should be 0 during reset");
                errors = errors + 1;
            end
            if (smoothed_energy !== 32'd0) begin
                $display("  ERROR: smoothed_energy should be 0 during reset");
                errors = errors + 1;
            end
            if (noise_floor !== 32'd0) begin
                $display("  ERROR: noise_floor should be 0 during reset");
                errors = errors + 1;
            end
            if (zero_cross_rate !== 16'd0) begin
                $display("  ERROR: zero_cross_rate should be 0 during reset");
                errors = errors + 1;
            end
        end
    endtask
    
    // Helper task: Print header
    task print_header();
        begin
            $display("========================================");
            $display("VAD Module Testbench");
            $display("========================================");
            $display("Configuration:");
            $display("  Sample Rate: %0d Hz", SAMPLE_RATE);
            $display("  Clock Frequency: %0d MHz", CLK_FREQ/1000000);
            $display("  Window Size: %0d samples (%0d ms)", SAMPLES_PER_WINDOW, 10);
            $display("  Hangover: %0d samples (%0d ms)", HANGOVER_SAMPLES, 300);
            $display("  Pre-trigger: %0d samples (%0d ms)", PRE_TRIGGER_SAMPLES, 200);
            $display("  ZCR Range: %0d - %0d", 15, 45);
            $display("========================================\n");
        end
    endtask
    
    // Helper task: Print summary
    task print_summary();
        begin
            $display("\n========================================");
            $display("Test Summary");
            $display("========================================");
            $display("Total Test Cases: 10");
            $display("Total Errors: %0d", errors);
            
            if (errors == 0) begin
                $display("\033[0;32mAll tests PASSED!\033[0m");
            end else begin
                $display("\033[0;31mSome tests FAILED!\033[0m");
            end
            $display("========================================");
        end
    endtask
    
    // Monitor for waveform dumping
    initial begin
        $dumpfile("tb_vad.vcd");
        $dumpvars(0, tb_vad);
    end
    
    // Assertion: Check sample_valid timing
    always @(posedge clk) begin
        if (sample_valid) begin
            #1; // Small delay
            if (sample_valid !== 1'b1) begin
                $display("ERROR: sample_valid should be stable for full clock cycle");
            end
        end
    end

endmodule
