// tb_aer_pipeline.v - Robust Testbench with Monitoring

`timescale 1ns/1ps

module tb_aer_pipeline;

    parameter CLK_PERIOD = 10;

    reg clk, rst_n, aer_valid;
    reg [23:0] aer_data;

    wire [3:0] channel_Id;
    wire [31:0] timestamp;
    wire timestamp_valid, spike_detected, window_start;
    wire fifo_full, fifo_empty;

    aer_pipeline dut (
        .clk(clk), .rst_n(rst_n),
        .aer_data(aer_data), .aer_valid(aer_valid),
        .channel_Id(channel_Id), .timestamp(timestamp),
        .timestamp_valid(timestamp_valid), .spike_detected(spike_detected),
        .window_start(window_start), .fifo_full(fifo_full), .fifo_empty(fifo_empty)
    );

    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    // Monitor all important signals
    initial begin
        $monitor("[%0t] valid=%b | ch=%h | ts=%h | spike=%b | empty=%b", 
                 $time, timestamp_valid, channel_Id, timestamp, spike_detected, fifo_empty);
    end

    initial begin
        $display("=== AER Pipeline Timing Fix Test ===");
        
        // Reset
        rst_n = 0; aer_valid = 0; aer_data = 0;
        #30;  
        rst_n = 1; 
        #20;

        // Inject Packet: Ch=A, Ts=0x123
        $display(">> Injecting Packet...");
        aer_data = 24'hA00123; 
        aer_valid = 1; 
        #10; 
        aer_valid = 0;

        // Wait for pipeline latency (~6 cycles = 60ns) + margin
        #200;

        // Final Check
        $display(">> Running Checks...");
        if (channel_Id === 4'hA) 
            $display("[PASS] Channel ID = %0h", channel_Id);
        else 
            $error("[FAIL] Channel ID = %0h (Expected A)", channel_Id);

        if (timestamp === 32'h00000123) 
            $display("[PASS] Timestamp = %0h", timestamp);
        else 
            $error("[FAIL] Timestamp = %0h (Expected 00000123)", timestamp);

        #50;
        $display("=== Test Complete ===");
        $finish;
    end

endmodule
