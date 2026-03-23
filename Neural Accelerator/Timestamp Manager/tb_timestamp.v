module tb_timestamp();
    reg clk;
    reg rst_n;
    reg [19:0] timestamp;
    reg ts_valid;
    reg window_open;
    wire [31:0] ts_abs;
    wire ts_abs_valid;
    wire [31:0] window_start;
    wire [19:0] window_offset;
    
    timestamp_manager uut1(
    .clk(clk),
    .rst_n(rst_n),
    .timestamp(timestamp),
    .ts_valid(ts_valid),
    .window_open(window_open),
    .ts_abs(ts_abs),
    .ts_abs_valid(ts_abs_valid),
    .window_start(window_start),
    .window_offset(window_offset));
    
    initial begin 
    clk = 0;
    forever #5 clk =~clk;
    end
    
    integer fail_count;
    
    task send_event;
    input [19:0] ts;
    begin
        @(negedge clk);
        timestamp = ts;
        ts_valid = 1'b1;
        @(posedge clk); #1;
        ts_valid = 1'b0;
        end
    endtask
    
    
    task pulse_window_open;
    begin
        @(negedge clk);
        window_open = 1'b1;
        @(posedge clk); #1;
        window_open = 1'b0;
    end
    endtask
    
    task check;
    input [127:0] label;
    input [63:0]  expected;
    input [63:0]  actual;
    begin
        if (expected === actual) begin
            $display("[PASS] %s  expected=%0d  got=%0d", label, expected, actual);
        end else begin
            $display("[FAIL] %s  expected=%0d  got=%0d", label, expected, actual);
            fail_count = fail_count + 1;
        end
    end
    endtask
    
    initial begin
    fail_count  = 0;
    rst_n     = 1'b0;
    timestamp = 20'd0;
    ts_valid = 1'b0;
    window_open = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk); #1;
    
    $display("--- TC1: Normal event stream ---");
    send_event(20'd100);
    check("TC1 ts_abs[0]     ", 32'd100,   ts_abs);
    check("TC1 ts_abs_valid  ", 64'd1,      ts_abs_valid);
    send_event(20'd200);
    check("TC1 ts_abs[1]     ", 32'd200,   ts_abs);
    send_event(20'd1000);
    check("TC1 ts_abs[2]     ", 32'd1000,  ts_abs);

        $display("--- TC2: Rollover detection ---");
 
        // Bring ts_prev close to rollover boundary
        send_event(20'hFFF00);   // ts_prev = 0xFFF00
        check("TC2 pre-rollover  ", {12'd0, 20'hFFF00}, ts_abs);
 
        // Now send a small ts - this should trigger rollover
        // diff = 0xFFF00 - 0x00010 = 0xFFEF0 > 0x80000 → rollover
        send_event(20'h00010);
        // After rollover: rollover_cnt = 1, ts_abs = {1, 0x00010}
        check("TC2 post-rollover ", {12'd1, 20'h00010}, ts_abs);
 
        // =================================================================
        // TC3 - window_open latches correct window_start
        // =================================================================
        $display("--- TC3: window_open latch ---");
 
        // Current ts_abs_comb = {1, 0x00010} = 0x00100010
        // Fire window_open - window_start should capture ts_abs_comb
        pulse_window_open;
        check("TC3 window_start  ", {12'd1, 20'h00010}, window_start);
 
        // =================================================================
        // TC4 - window_offset calculation
        // =================================================================
        $display("--- TC4: window_offset ---");
 
        // window_start = {1, 0x00010} = 0x00100010
        // Send event at ts = 0x00050 (same rollover epoch)
        // ts_abs_comb = {1, 0x00050}
        // offset = {1,0x50} - {1,0x10} = 0x40 = 64
        send_event(20'h00050);
        check("TC4 window_offset ", 20'd64, window_offset);
 
        // Send event at ts = 0x00110
        // offset = {1,0x110} - {1,0x10} = 0x100 = 256
        send_event(20'h00110);
        check("TC4 offset 0x100  ", 20'd256, window_offset);
 
        // =================================================================
        // TC5 - Saturation: offset > 20-bit max
        // =================================================================
        $display("--- TC5: offset saturation ---");
 
        pulse_window_open;  // window_start now latches current ts_abs_comb = {1, 0x00110}
 
        // Roll over once more: send ts near 0xFFFFF, then ts = 5
        send_event(20'hFFFE0);
        send_event(20'h00005);  // rollover_cnt → 2, ts_abs_comb = {2, 0x00005}
        // offset = {2,5} - {1,0x110} = 0x100000 - 0x10B = large → saturate
        check("TC5 saturation    ", 20'hFFFFF, window_offset);
 
        // =================================================================
        // TC6 - Multiple rollovers accumulate correctly
        // =================================================================
        $display("--- TC6: Multiple rollovers ---");
 
        // rollover_cnt is currently 2 after TC5
        // Do 3 more rollovers
        send_event(20'hFFF00);
        send_event(20'h00001);  // cnt=3
        send_event(20'hFFF00);
        send_event(20'h00001);  // cnt=4
        send_event(20'hFFF00);
        send_event(20'h00001);  // cnt=5
 
        check("TC6 rollover_cnt=5", {12'd5, 20'h00001}, ts_abs);
 
        // =================================================================
        // TC7 - reset_n clears all state
        // =================================================================
        $display("--- TC7: reset_n ---");
 
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) @(posedge clk); #1;
 
        check("TC7 ts_abs=0      ", 32'd0, ts_abs);
        check("TC7 ts_abs_valid=0", 1'd0,  ts_abs_valid);
        check("TC7 window_start=0", 32'd0, window_start);
 
        rst_n = 1'b1;
 
        // =================================================================
        // Summary
        // =================================================================
        @(posedge clk); #1;
        if (fail_count == 0)
            $display("ALL TESTS PASSED (%0d failures)", fail_count);
        else
            $display("TESTS COMPLETED - %0d FAILURE(S)", fail_count);
 
        $finish;
    end
 
    // Timeout watchdog - kill sim if it hangs
    initial begin
        #50000;
        $display("[FAIL] TIMEOUT - simulation hung");
        $finish;
    end
 
endmodule
