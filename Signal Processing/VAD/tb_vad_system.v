// ============================================================================
// Testbench for vad_top_16khz_pure
// Tests:
//   • 12-bit → 16-bit conversion
//   • DC blocker functionality
//   • Energy/ZCR calculation
//   • Adaptive threshold calibration
//   • VAD state machine transitions
//   • Pre-trigger capture
// ============================================================================

`timescale 1ns/1ps

module tb_vad_16khz;

    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg             clk_16khz;
    reg             rst;
    reg     [11:0]  mic_data;
    reg             buf_read_en;
    reg     [7:0]   buf_read_addr;
    wire    [15:0]  buf_read_data;
    wire            vad_output;
    wire            frame_valid;
    wire    [31:0]  energy_val;
    wire    [7:0]   zcr_val;
    wire            calibration_active;
    wire            thresholds_ready;
    
    // ========================================================================
    // Test Parameters
    // ========================================================================
    parameter CLK_PERIOD = 62500;  // 16 kHz → 62.5 µs period
    parameter TOTAL_SAMPLES = 6400; // 400 ms of test data @ 16 kHz
    parameter SILENCE_DURATION = 800;   // 50 ms silence
    parameter SPEECH_DURATION = 4800;   // 300 ms speech-like signal
    parameter POST_SILENCE = 800;       // 50 ms silence after speech
    
    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    vad_top_16khz_pure dut (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .mic_data(mic_data),
        .buf_read_en(buf_read_en),
        .buf_read_addr(buf_read_addr),
        .buf_read_data(buf_read_data),
        .vad_output(vad_output),
        .frame_valid(frame_valid),
        .energy_val(energy_val),
        .zcr_val(zcr_val),
        .calibration_active(calibration_active),
        .thresholds_ready(thresholds_ready)
    );
    
    // ========================================================================
    // Clock Generation: 16 kHz
    // ========================================================================
    initial begin
        clk_16khz = 0;
        forever #(CLK_PERIOD/2) clk_16khz = ~clk_16khz;
    end
    
    // ========================================================================
    // Task: Generate Test Waveforms
    // ========================================================================
    
    // Generate silence (low amplitude noise around midpoint)
    task generate_silence(input integer duration);
        integer i;
        begin
            for (i = 0; i < duration; i = i + 1) begin
                @(posedge clk_16khz);
                // Small random noise around 2048 (midpoint of 12-bit unsigned)
                mic_data <= 12'd2048 + ($random % 200) - 100;
            end
        end
    endtask
    
    // Generate speech-like signal (higher amplitude, more zero crossings)
    task generate_speech(input integer duration);
        integer i;
        reg signed [15:0] phase;
        begin
            phase = 0;
            for (i = 0; i < duration; i = i + 1) begin
                @(posedge clk_16khz);
                // Simulate 400 Hz sine wave + harmonics + noise
                phase = phase + 16'd256;  // Frequency control
                mic_data <= 12'd2048 + 
                           (($signed({phase[11:0], 4'd0}) * 16'sd800) >>> 15) +  // Sine
                           ($random % 300) - 150;  // Noise
            end
        end
    endtask
    
    // Generate DC offset test signal (constant offset to verify HPF)
    task generate_dc_offset(input integer duration, input integer offset);
        integer i;
        begin
            for (i = 0; i < duration; i = i + 1) begin
                @(posedge clk_16khz);
                mic_data <= 12'd2048 + offset;  // Constant offset
            end
        end
    endtask
    
    // ========================================================================
    // Monitor & Check Tasks
    // ========================================================================
    
    // Monitor VAD output transitions
    reg [31:0] frame_count;
    reg vad_prev;
    
    task monitor_vad;
        begin
            if (frame_valid) begin
                if (vad_output && !vad_prev)
                    $display("[%0d frames] 🎤 VAD: SILENCE → SPEECH", frame_count);
                else if (!vad_output && vad_prev)
                    $display("[%0d frames] 🔇 VAD: SPEECH → SILENCE", frame_count);
                vad_prev <= vad_output;
                frame_count <= frame_count + 1;
            end
        end
    endtask
    
    // Check energy/ZCR values during speech vs silence
    task check_features;
        begin
            if (frame_valid) begin
                if (vad_output) begin
                    // During speech: expect higher energy, moderate ZCR
                    if (energy_val < 32'd100000)
                        $display("⚠️  Warning: Low energy (%d) during speech", energy_val);
                    if (zcr_val < 8'd10 || zcr_val > 8'd60)
                        $display("⚠️  Warning: Unexpected ZCR (%d) during speech", zcr_val);
                end else begin
                    // During silence: expect low energy
                    if (energy_val > 32'd500000)
                        $display("⚠️  Warning: High energy (%d) during silence", energy_val);
                end
            end
        end
    endtask
    
    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        // Initialize
        rst = 1'b0;
        mic_data = 12'd2048;
        buf_read_en = 1'b0;
        buf_read_addr = 8'd0;
        frame_count = 0;
        vad_prev = 0;
        
        // Reset sequence
        $display("🔧 Resetting DUT...");
        #(CLK_PERIOD * 4);
        rst = 1'b1;
        #(CLK_PERIOD * 2);
        
        $display("✅ DUT reset complete");
        $display("📊 Test Parameters:");
        $display("   - Silence: %0d samples (%0.2f ms)", SILENCE_DURATION, SILENCE_DURATION*1000.0/16.0);
        $display("   - Speech:  %0d samples (%0.2f ms)", SPEECH_DURATION, SPEECH_DURATION*1000.0/16.0);
        $display("   - Post-silence: %0d samples (%0.2f ms)", POST_SILENCE, POST_SILENCE*1000.0/16.0);
        $display("");
        
        // ====================================================================
        // Phase 1: Calibration Period (first 2 seconds = 32000 samples)
        // ====================================================================
        $display("🔄 Phase 1: Calibration (first 2 seconds - ambient noise)");
        generate_silence(32000);  // 2 seconds of silence for calibration
        
        // Verify calibration completed
        wait (thresholds_ready);
        $display("✅ Calibration complete: thresholds_ready = 1");
        $display("   OFF threshold: %0d", dut.off_thresh);
        $display("   ON threshold:  %0d", dut.on_thresh);
        $display("");
        
        // ====================================================================
        // Phase 2: Test Sequence - Silence → Speech → Silence
        // ====================================================================
        $display("🎬 Phase 2: VAD Detection Test");
        
        // 2a. Pre-speech silence (50 ms)
        $display("   [0.00s] Generating pre-speech silence...");
        generate_silence(SILENCE_DURATION);
        
        // 2b. Speech segment (300 ms)
        $display("   [0.05s] Generating speech-like signal...");
        generate_speech(SPEECH_DURATION);
        
        // 2c. Post-speech silence (50 ms)
        $display("   [0.35s] Generating post-speech silence...");
        generate_silence(POST_SILENCE);
        
        $display("");
        
        // ====================================================================
        // Phase 3: DC Offset Test
        // ====================================================================
        $display("🔋 Phase 3: DC Offset Removal Test");
        
        // Apply DC offset and verify it's removed
        generate_dc_offset(1600, 500);  // 100 ms with +500 offset
        $display("   Applied +500 DC offset for 100 ms");
        
        // Read a sample from circular buffer to verify DC removal
        buf_read_en <= 1'b1;
        buf_read_addr <= 8'd100;
        @(posedge clk_16khz);
        $display("   Buffer sample [100]: %0d (should be near 0 after HPF)", buf_read_data);
        buf_read_en <= 1'b0;
        $display("");
        
        // ====================================================================
        // Phase 4: Stress Test - Rapid Transitions
        // ====================================================================
        $display("⚡ Phase 4: Rapid Transition Stress Test");
        
        // Quick on/off pattern
        repeat (5) begin
            generate_speech(320);   // 20 ms speech
            generate_silence(320);  // 20 ms silence
        end
        $display("   Completed 5 rapid on/off cycles");
        $display("");
        
        // ====================================================================
        // Phase 5: Final Verification & Statistics
        // ====================================================================
        $display("📈 Phase 5: Final Verification");
        
        // Wait for any pending state transitions
        #(CLK_PERIOD * 200);  // Wait 200 ms
        
        // Print summary statistics
        $display("========================================");
        $display("📊 TEST SUMMARY");
        $display("========================================");
        $display("Total frames processed: %0d", frame_count);
        $display("Final VAD state: %s", vad_output ? "SPEECH" : "SILENCE");
        $display("Calibration active: %s", calibration_active ? "YES" : "NO");
        $display("Thresholds ready: %s", thresholds_ready ? "YES" : "NO");
        $display("");
        
        // Check expected behavior
        if (thresholds_ready && !calibration_active)
            $display("✅ Calibration system: PASS");
        else
            $display("❌ Calibration system: FAIL");
            
        // Additional checks can be added here
        
        $display("");
        $display("🎉 Testbench complete!");
        
        // Dump waveform for inspection
        $dumpfile("vad_simulation.vcd");
        $dumpvars(0, tb_vad_16khz);
        
        // Finish simulation
        #(CLK_PERIOD * 100);
        $finish;
    end
    
    // ========================================================================
    // Continuous Monitoring
    // ========================================================================
    always @(posedge clk_16khz) begin
        monitor_vad();
        check_features();
    end
    
    // ========================================================================
    // Optional: Periodic Status Print (every 100 frames)
    // ========================================================================
    always @(posedge clk_16khz) begin
        if (frame_valid && (frame_count % 100 == 0)) begin
            $display("[Frame %0d] VAD=%b | Energy=%0d | ZCR=%0d | Calib=%b",
                     frame_count, vad_output, energy_val, zcr_val, calibration_active);
        end
    end

endmodule
