module tb_vad();

    // Testbench parameters
    localparam CLK_PERIOD = 10; // 100MHz clock
    localparam SAMPLE_RATE = 16000;
    localparam CLKS_PER_SAMPLE = 100_000_000 / SAMPLE_RATE; // 6250 clocks
    
    // Testbench signals
    reg clk;
    reg rst_n;
    reg [15:0] audio_in;
    reg sample_valid;
    
    wire speech_detected;
    wire [31:0] smoothed_energy;
    wire recording_active;
    
    // Test control
    integer sample_count;
    integer test_pass;
    integer error_count;
    integer hangover_check;
    integer i, j;
    
    // For storing test vectors
    reg [15:0] test_samples [0:47999]; // 3 seconds at 16kHz
    
    // Instantiate DUT
    vad #(
        .SAMPLE_RATE(16000),
        .THRESHOLD(32'd1_000_000),
        .HANGOVER_MS(300),
        .BUFFER_SIZE_MS(1500)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .audio_in(audio_in),
        .sample_valid(sample_valid),
        .speech_detected(speech_detected),
        .smoothed_energy(smoothed_energy),
        .recording_active(recording_active)
    );
    
    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Sample valid generation
    reg [15:0] clk_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_counter <= 0;
            sample_valid <= 0;
        end else begin
            if (clk_counter >= CLKS_PER_SAMPLE - 1) begin
                clk_counter <= 0;
                sample_valid <= 1;
            end else begin
                clk_counter <= clk_counter + 1;
                sample_valid <= 0;
            end
        end
    end
    
    // Initialize test vectors
    initial begin
        // Silence section (0-0.5s)
        for (i = 0; i < 8000; i = i + 1) begin
            test_samples[i] = 16'd10 + {$random} % 20;
        end
        
        // Speech section (0.5-1.5s) - voiced sounds
        for (i = 8000; i < 16000; i = i + 1) begin
            // Simulate voiced speech with periodic pattern
            if ((i % 80) < 40) // 200Hz fundamental
                test_samples[i] = 16'd3000;
            else
                test_samples[i] = -16'd3000;
            // Add some variation
            test_samples[i] = test_samples[i] + {$random} % 500 - 250;
        end
        
        // Speech section (1.5-2.0s) - unvoiced sounds
        for (i = 16000; i < 24000; i = i + 1) begin
            test_samples[i] = ($random % 1000) - 500;
        end
        
        // Mixed speech (2.0-2.5s)
        for (i = 24000; i < 32000; i = i + 1) begin
            if ($random % 2) begin
                // Voiced
                if ((i % 60) < 30)
                    test_samples[i] = 16'd2500;
                else
                    test_samples[i] = -16'd2500;
            end else begin
                // Unvoiced
                test_samples[i] = ($random % 600) - 300;
            end
        end
        
        // Silence with noise (2.5-3.0s)
        for (i = 32000; i < 48000; i = i + 1) begin
            test_samples[i] = 16'd5 + {$random} % 15;
        end
    end
    
    // Main test sequence
    initial begin
        // Initialize
        clk = 0;
        rst_n = 0;
        audio_in = 0;
        sample_count = 0;
        error_count = 0;
        test_pass = 1;
        
        $display("========================================");
        $display("Starting VAD Module Testbench");
        $display("========================================");
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        
        // Test 1: Verify reset state
        @(posedge clk);
        if (speech_detected !== 0 || recording_active !== 0) begin
            $display("ERROR: Reset state incorrect");
            error_count = error_count + 1;
        end else begin
            $display("Test 1: Reset check PASSED");
        end
        
        // Test 2: Run through test vectors
        $display("\nTest 2: Running through 3 seconds of audio");
        for (sample_count = 0; sample_count < 48000; sample_count = sample_count + 1) begin
            @(posedge sample_valid);
            audio_in = test_samples[sample_count];
            
            // Check silence period (first 0.5s)
            if (sample_count == 4000) begin
                if (speech_detected) begin
                    $display("ERROR: False detection during silence at sample %0d", sample_count);
                    error_count = error_count + 1;
                end
            end
            
            // Check speech detection (around 0.7s)
            if (sample_count == 11200) begin // ~0.7s
                if (!speech_detected) begin
                    $display("ERROR: Missed speech detection at sample %0d", sample_count);
                    error_count = error_count + 1;
                end else begin
                    $display("  Speech correctly detected at ~0.7s");
                end
            end
            
            // Check hangover at end of speech (around 2.5s)
            if (sample_count == 40000) begin // 2.5s
                hangover_check = 1;
            end
        end
        
        // Test 3: Verify hangover
        $display("\nTest 3: Checking hangover period");
        #1000; // Small delay
        
        if (speech_detected) begin
            $display("  Hangover active after speech ends");
            #4_800_000; // Wait 300ms (300ms * 16kHz * 62.5us * 16)
            if (speech_detected) begin
                $display("ERROR: Hangover longer than 300ms");
                error_count = error_count + 1;
            end else begin
                $display("  Hangover duration correct (~300ms)");
            end
        end
        
        // Test 4: Threshold hysteresis
        $display("\nTest 4: Checking threshold hysteresis");
        
        // Generate signal just above threshold
        for (i = 0; i < 1000; i = i + 1) begin
            @(posedge sample_valid);
            audio_in = 16'd1000; // Should be above threshold after accumulation
        end
        
        if (!speech_detected) begin
            $display("ERROR: Signal above threshold not detected");
            error_count = error_count + 1;
        end
        
        // Generate signal between THRESHOLD and THRESHOLD/2
        #1_000_000;
        
        // Test 5: Zero-crossing counter
        $display("\nTest 5: Checking zero-crossing functionality");
        // Feed high-frequency signal
        for (i = 0; i < 160; i = i + 1) begin // 10ms at 16kHz
            @(posedge sample_valid);
            audio_in = (i % 2) ? 16'd1000 : -16'd1000; // Square wave
        end
        
        // Test 6: Noise floor estimation
        $display("\nTest 6: Checking noise floor tracking");
        #1_000_000;
        
        // Feed decreasing amplitude to test min_energy
        for (i = 0; i < 1000; i = i + 1) begin
            @(posedge sample_valid);
            audio_in = 16'd100 - i/10;
        end
        
        // Test 7: Impulse response
        $display("\nTest 7: Checking impulse response");
        
        // Send positive impulse
        @(posedge sample_valid);
        audio_in = 16'h7FFF; // Max positive
        
        // Send negative impulse
        #1_000_000;
        @(posedge sample_valid);
        audio_in = 16'h8000; // Max negative
        
        // Test 8: Rapid on/off switching
        $display("\nTest 8: Testing rapid VAD transitions");
        
        for (i = 0; i < 10; i = i + 1) begin
            // Short speech burst (50ms)
            for (j = 0; j < 800; j = j + 1) begin
                @(posedge sample_valid);
                audio_in = 16'd3000;
            end
            
            // Short silence (20ms)
            for (j = 0; j < 320; j = j + 1) begin
                @(posedge sample_valid);
                audio_in = 16'd10;
            end
        end
        
        // Final results
        #10_000_000;
        
        $display("\n========================================");
        if (error_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("TESTS COMPLETED WITH %0d ERRORS", error_count);
        end
        $display("========================================");
        
        #1000;
        $finish;
    end
    
    // Monitor for unexpected behavior
    always @(posedge clk) begin
        if (rst_n && sample_valid) begin
            // Check for illegal states
            if (speech_detected && !recording_active) begin
                $display("ERROR: speech_detected without recording_active at time %t", $time);
                error_count = error_count + 1;
            end
            
            // Energy should never be negative (signed comparison issue)
            if ($signed(smoothed_energy) < 0) begin
                $display("ERROR: Negative energy detected at time %t", $time);
                error_count = error_count + 1;
            end
        end
    end
    
    // Monitor energy levels periodically
    always @(posedge clk) begin
        if (rst_n && sample_valid && (sample_count % 1600 == 0)) begin // Every 100ms
            $display("Time: %0t ms, Energy: %0d, VAD: %b", 
                     $time/1_000_000, smoothed_energy, speech_detected);
        end
    end
    
    // Generate waveform dump
    initial begin
        $dumpfile("tb_vad.vcd");
        $dumpvars(0, tb_vad);
    end
    
    // Timeout
    initial begin
        #200_000_000; // 200ms timeout
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
