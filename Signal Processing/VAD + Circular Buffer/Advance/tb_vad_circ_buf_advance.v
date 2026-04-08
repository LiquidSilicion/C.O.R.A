`timescale 1ns/1ps

module tb_vad_circ_buf_advance();

    localparam CLK_PERIOD_100M = 10;
    localparam PCM_PERIOD      = 6250;
    
    reg         clk_100m;
    reg         rst_n;
    reg  [15:0] pcm_in;
    reg         pcm_valid;
    wire [15:0] speech_raw;
    wire        audio_valid;
    wire        speech_valid;
    wire [31:0] dbg_energy;
    wire [31:0] dbg_noise_floor;
    wire [31:0] dbg_zcr;
    wire        vad_debug_trigger;
    
    integer     pcm_count;
    integer     audio_out_count;
    integer     test_errors;
    integer     i;
    integer pretrig_count;
    
    vad_circ_buf_advance dut (
        .clk_100m          (clk_100m),
        .rst_n             (rst_n),
        .pcm_in            (pcm_in),
        .pcm_valid         (pcm_valid),
        .speech_raw        (speech_raw),
        .audio_valid       (audio_valid),
        .speech_valid      (speech_valid),
        .dbg_energy        (dbg_energy),
        .dbg_noise_floor   (dbg_noise_floor),
        .dbg_zcr           (dbg_zcr),
        .vad_debug_trigger (vad_debug_trigger)
    );
    
    initial begin
        clk_100m = 0;
        forever #5 clk_100m = ~clk_100m;
    end
    
    always @(posedge clk_100m) begin
        if (pcm_valid) pcm_count = pcm_count + 1;
        if (audio_valid) audio_out_count = audio_out_count + 1;
    end
    
    // FIXED: Generate realistic speech (not alternating every sample)
    task generate_pcm_samples;
        input [31:0] num_samples;
        input [15:0] amplitude;
        integer j;
        reg [15:0] sample_val;
        begin
            for (j = 0; j < num_samples; j = j + 1) begin
                @(posedge clk_100m);
                pcm_valid = 1;
                // FIXED: Sine-like wave (not max ZCR)
                // This gives ZCR ~20-30 per window, not 160
                sample_val = amplitude * (($random % 1000) - 500) / 1000;
                pcm_in = sample_val;
                @(posedge clk_100m);
                pcm_valid = 0;
                #(PCM_PERIOD - 20);
            end
        end
    endtask
    
    // Generate pure silence for noise floor adaptation
    task generate_silence;
        input [31:0] num_samples;
        integer j;
        begin
            for (j = 0; j < num_samples; j = j + 1) begin
                @(posedge clk_100m);
                pcm_valid = 1;
                pcm_in = 16'sd10;  // Small non-zero value (mic noise)
                @(posedge clk_100m);
                pcm_valid = 0;
                #(PCM_PERIOD - 20);
            end
        end
    endtask
    
    initial begin
        rst_n = 0;
        pcm_valid = 0;
        pcm_in = 0;
        pcm_count = 0;
        audio_out_count = 0;
        test_errors = 0;
        
        $display("========================================");
        $display("CORA VAD Hybrid Testbench - FIXED");
        $display("========================================");
        
        #100;
        rst_n = 1;
        #100;
        $display("[%0t] Reset Complete", $time);
        
        // TEST 1: Silence (noise floor should adapt)
        $display("[%0t] TEST 1: Silence Period (Noise Floor Adapt)", $time);
        generate_silence(8000);  // 500ms with small noise
        if (speech_valid === 0) begin
            $display("[%0t] TEST 1 PASSED", $time);
            $display("  Noise Floor after silence: %d", dbg_noise_floor);
        end else begin
            $display("[ERROR] False trigger during silence");
            test_errors = test_errors + 1;
        end
        
        // TEST 2: Speech Trigger
        $display("[%0t] TEST 2: Speech Trigger", $time);
        generate_pcm_samples(1000, 10000);  // Realistic speech
        
        i = 0;
        while (speech_valid === 0 && i < 100000) begin
            @(posedge clk_100m);
            i = i + 1;
        end
        
        if (speech_valid === 1) begin
            $display("[%0t] TEST 2 PASSED: VAD Triggered!", $time);
            $display("  Energy: %d, Noise Floor: %d, ZCR: %d", 
                     dbg_energy, dbg_noise_floor, dbg_zcr);
        end else begin
            $display("[ERROR] VAD did not trigger");
            test_errors = test_errors + 1;
        end
        
        // TEST 3: Pre-trigger Burst
        $display("[%0t] TEST 3: Pre-trigger Burst", $time);
        pretrig_count = 0;
        repeat (4000) begin
            @(posedge clk_100m);
            if (audio_valid === 1) pretrig_count = pretrig_count + 1;
        end
        $display("[%0t] Pre-trigger samples: %d", $time, pretrig_count);
        if (pretrig_count >= 2000)
            $display("[%0t] TEST 3 PASSED", $time);
        else begin
            $display("[ERROR] Pre-trigger incomplete");
            test_errors = test_errors + 1;
        end
        
        // TEST 4: Hangover
        $display("[%0t] TEST 4: Hangover Test", $time);
        generate_silence(6000);  // Silence for hangover period
        
        // Wait for speech_valid to drop (should take ~300ms = 4800 samples)
        i = 0;
        while (speech_valid === 1 && i < 500000) begin
            @(posedge clk_100m);
            i = i + 1;
        end
        
        if (speech_valid === 0) begin
            $display("[%0t] TEST 4 PASSED: Hangover complete", $time);
        end else begin
            $display("[ERROR] Hangover did not complete after %d cycles", i);
            test_errors = test_errors + 1;
        end
        
        #100000;
        $display("========================================");
        $display("SIMULATION COMPLETE");
        $display("PCM: %d, Audio Out: %d, Errors: %d", 
                 pcm_count, audio_out_count, test_errors);
        $display("========================================");
        
        if (test_errors === 0) $display("ALL TESTS PASSED!");
        else $display("TESTS FAILED!");
        
        $finish;
    end
    
    initial begin
        $dumpfile("cora_vad_hybrid_test.vcd");
        $dumpvars(0, tb_cora_vad_circ_buf_hybrid);
    end
    
endmodule
