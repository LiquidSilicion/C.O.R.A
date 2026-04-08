module tb_cora_vad_circ_buf;

    localparam CLK_PERIOD_100M = 10;
    localparam PCM_PERIOD      = 6250;  // 62.5µs @ 100MHz = 16kHz
    
    reg         clk_100m;
    reg         rst_n;
    reg  [15:0] pcm_in;
    reg         pcm_valid;
    wire [15:0] speech_raw;
    wire        audio_valid;
    wire        speech_valid;
    wire [31:0] dbg_energy;
    wire [31:0] dbg_zcr;
    
    integer     pcm_count;
    integer     audio_out_count;
    integer     test_errors;
    integer     i;
    integer pretrig_count;
    
    cora_vad_circ_buf dut (
        .clk_100m      (clk_100m),
        .rst_n         (rst_n),
        .pcm_in        (pcm_in),
        .pcm_valid     (pcm_valid),
        .speech_raw    (speech_raw),
        .audio_valid   (audio_valid),
        .speech_valid  (speech_valid),
        .dbg_energy    (dbg_energy),
        .dbg_zcr       (dbg_zcr)
    );
    
    // Clock
    initial begin
        clk_100m = 0;
        forever #5 clk_100m = ~clk_100m;
    end
    
    // Monitors
    always @(posedge clk_100m) begin
        if (pcm_valid)
            pcm_count = pcm_count + 1;
        if (audio_valid)
            audio_out_count = audio_out_count + 1;
    end
    
    // Generate exactly N PCM pulses at 16kHz
    task generate_pcm_samples;
        input [31:0] num_samples;
        input [15:0] amplitude;
        integer j;
        begin
            for (j = 0; j < num_samples; j = j + 1) begin
                @(posedge clk_100m);
                pcm_valid = 1;
                // Alternating pattern for max ZCR
                if (j % 2 == 0)
                    pcm_in = amplitude;
                else
                    pcm_in = -amplitude;
                @(posedge clk_100m);
                pcm_valid = 0;
                #(PCM_PERIOD - 20);  // Wait rest of 16kHz period
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
        $display("CORA VAD Testbench - FIXED");
        $display("========================================");
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        $display("[%0t] Reset Complete", $time);
        
        // TEST 1: Silence (no triggers)
        $display("[%0t] TEST 1: Silence Period", $time);
        generate_pcm_samples(8000, 0);  // 500ms silence
        if (speech_valid === 0)
            $display("[%0t] TEST 1 PASSED", $time);
        else begin
            $display("[ERROR] False trigger");
            test_errors = test_errors + 1;
        end
        
        // TEST 2: Speech Trigger
        $display("[%0t] TEST 2: Speech Trigger", $time);
        generate_pcm_samples(500, 10000);  // High amplitude speech
        
        // Wait for speech_valid
        i = 0;
        while (speech_valid === 0 && i < 100000) begin
            @(posedge clk_100m);
            i = i + 1;
        end
        
        if (speech_valid === 1) begin
            $display("[%0t] TEST 2 PASSED: VAD Triggered! Energy=%d ZCR=%d", 
                     $time, dbg_energy, dbg_zcr);
        end else begin
            $display("[ERROR] VAD did not trigger");
            test_errors = test_errors + 1;
        end
        
        // TEST 3: Verify Pre-trigger Burst
        $display("[%0t] TEST 3: Pre-trigger Burst", $time);
        pretrig_count = 0;
        repeat (4000) begin
            @(posedge clk_100m);
            if (audio_valid === 1)
                pretrig_count = pretrig_count + 1;
        end
        $display("[%0t] Pre-trigger samples: %d", $time, pretrig_count);
        
        // TEST 4: Hangover
        $display("[%0t] TEST 4: Hangover Test", $time);
        generate_pcm_samples(6000, 0);  // Silence for hangover period
        
        // Wait for speech_valid to drop
        i = 0;
        while (speech_valid === 1 && i < 200000) begin
            @(posedge clk_100m);
            i = i + 1;
        end
        
        if (speech_valid === 0)
            $display("[%0t] TEST 4 PASSED: Hangover complete", $time);
        else begin
            $display("[ERROR] Hangover did not complete");
            test_errors = test_errors + 1;
        end
        
        // Summary
        #100000;
        $display("========================================");
        $display("SIMULATION COMPLETE");
        $display("PCM Samples: %d, Audio Out: %d, Errors: %d", 
                 pcm_count, audio_out_count, test_errors);
        $display("========================================");
        
        if (test_errors === 0)
            $display("ALL TESTS PASSED!");
        else
            $display("TESTS FAILED!");
        
        $finish;
    end
    
    initial begin
        $dumpfile("cora_vad_test.vcd");
        $dumpvars(0, tb_cora_vad_circ_buf);
    end
    
endmodule
