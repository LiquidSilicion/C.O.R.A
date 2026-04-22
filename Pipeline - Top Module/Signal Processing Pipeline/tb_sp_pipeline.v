`timescale 1ns / 1ps
module tb_sp_pipeline;
//==========================================================================
// 1. SIGNALS
//==========================================================================
reg         clk;
reg         rst_n;
wire [23:0] aer_packet;
wire        aer_valid;
wire        audio_done;

// Debug signals
wire [15:0] debug_rom;
wire [15:0] debug_emph;
wire [15:0] debug_env0;
wire [15:0] debug_spike_bus;

// Timeout counter (module-level reg to avoid automatic/static error)
reg [31:0] timeout_cnt;

    localparam MAX_CYCLES = 32'd200_000_000; // 2s @ 100MHz
//==========================================================================
// 2. UUT
//==========================================================================
sp_pipeline uut (
    .clk            (clk),
    .rst_n          (rst_n),
    .aer_packet     (aer_packet),
    .aer_valid      (aer_valid),
    .audio_done     (audio_done),
    .debug_rom      (debug_rom),
    .debug_emph     (debug_emph),
    .debug_env0     (debug_env0),
    .debug_spike_bus(debug_spike_bus)
);

//==========================================================================
// 3. CLOCK (100 MHz)
//==========================================================================
initial clk = 1'b0;
always #5 clk = ~clk;

//==========================================================================
// 4. TEST SEQUENCE
//==========================================================================
initial begin
    rst_n = 1'b0;
    
    $dumpfile("sp_pipeline_debug.vcd");
    $dumpvars(0, tb_sp_pipeline);

    $display("========================================");
    $display(" CORA SPIKE PIPELINE TESTBENCH");
    $display("========================================");
    
    #100;
    rst_n = 1'b1;
    $display("[%0t ps] Reset de-asserted. Starting...", $time);

    // Progress monitor
    #10_000_000;
    while (!audio_done) begin
        #10_000_000;
    end
    
    #2000;
    $display("[%0t ps] ✅ Simulation complete.", $time);
    $finish;
end

//==========================================================================
// 5. AER MONITOR
//==========================================================================
integer pkt_count = 0;
always @(posedge clk) begin
    if (aer_valid) begin
        pkt_count = pkt_count + 1;
        $display("[%0t ps] 📦 AER: CH=%0d TS=%0d (#%0d)", 
                 $time, aer_packet[23:20], aer_packet[19:0], pkt_count);
    end
end

//==========================================================================
// 6. TIMEOUT (Cycle-based, simulator-safe)
//==========================================================================
initial begin
    
    timeout_cnt = 32'd0;
    
    forever begin
        @(posedge clk);
        if (!rst_n) begin
            timeout_cnt <= 32'd0;
        end else if (audio_done) begin
            $display("[%0t ps] ✅ Completed in %0d cycles", $time, timeout_cnt);
            $finish;
        end else begin
            timeout_cnt <= timeout_cnt + 1'b1;
            if ((timeout_cnt % 32'd50_000_000) == 0 && timeout_cnt > 0) begin
                $display("[%0t ps] ⏳ Progress: %0d / %0d cycles", 
                         $time, timeout_cnt, MAX_CYCLES);
            end
            if (timeout_cnt >= MAX_CYCLES) begin
                $display("\n❌ TIMEOUT: audio_done not asserted after %0d cycles.", MAX_CYCLES);
                $display("Debug tips:");
                $display("  1. Check coefficients.mem exists and is hex-formatted");
                $display("  2. Verify pm_filter ports: .x_n / .y_n");
                $display("  3. Confirm ihc_top.sample_en is driven");
                $display("  4. Ensure lif_top.spike_bus is [15:0]");
                $finish;
            end
        end
    end
end

endmodule
