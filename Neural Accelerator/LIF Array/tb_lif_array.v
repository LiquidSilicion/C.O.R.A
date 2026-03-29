module tb_lif_array();
 
    localparam NH    = 2;
    localparam ALPHA = 16'h00E0;   // 0.875
    localparam THETA = 16'h0100;   // 1.0
 
    // ── DUT signals ──────────────────────────────────────────────────────────
    reg         clk, rst_n, clear_state;
    reg  [15:0] lif_acc;
    reg  [6:0]  lif_idx;
    reg         lif_wen, lif_capture;
    wire [NH-1:0] lif_spikes;
    wire          capture_done;
 
    // ── DUT ──────────────────────────────────────────────────────────────────
    lif_array #(.NH(NH), .ALPHA(ALPHA), .THETA(THETA)) dut (
        .clk(clk), .rst_n(rst_n), .clear_state(clear_state),
        .lif_acc(lif_acc), .lif_idx(lif_idx),
        .lif_wen(lif_wen), .lif_capture(lif_capture),
        .lif_spikes(lif_spikes), .capture_done(capture_done)
    );
 
    initial clk = 0;
    always #5 clk = ~clk;
 
    // ── helpers ───────────────────────────────────────────────────────────────
    integer fail_count;
 
    task check;
        input [127:0] label;
        input [63:0]  exp, got;
        begin
            if (exp === got)
                $display("[PASS]  %-24s  exp=0x%08h  got=0x%08h", label, exp, got);
            else begin
                $display("[FAIL]  %-24s  exp=0x%08h  got=0x%08h", label, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask
 
    // Drive one lif_wen pulse
    task write_accum;
        input [6:0]  idx;
        input [15:0] val;
        begin
            @(negedge clk);
            lif_idx = idx; lif_acc = val; lif_wen = 1;
            @(posedge clk); #1;
            lif_wen = 0;
        end
    endtask
 
    // Run a full capture cycle; wait for capture_done
    task do_capture;
        integer timeout;
        begin
            @(negedge clk);
            lif_capture = 1;
            @(posedge clk); #1;
            lif_capture = 0;
            timeout = 0;
            while (!capture_done && timeout < 500) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
            end
            if (timeout >= 500) begin
                $display("[FAIL]  capture_done never asserted");
                fail_count = fail_count + 1;
            end
        end
    endtask
 
    //--------------------------------------------------------------------------
    initial begin
        fail_count   = 0;
        rst_n        = 0;
        clear_state  = 0;
        lif_wen      = 0;
        lif_capture  = 0;
        lif_acc      = 0;
        lif_idx      = 0;
 
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1;
 
        // ── TC1: reset state ──────────────────────────────────────────────
        $display("--- TC1: reset state ---");
        check("vm[0]=0 after rst",   16'h0000, dut.vm[0]);
        check("vm[1]=0 after rst",   16'h0000, dut.vm[1]);
        check("spikes=0 after rst",  2'b00,    lif_spikes);
 
        // ── TC2: accumulator write ────────────────────────────────────────
        $display("--- TC2: accumulator write ---");
        write_accum(0, 16'h0080);   // 0.5 Q8.8
        write_accum(1, 16'h0040);   // 0.25 Q8.8
        @(posedge clk); #1;
        check("accum[0]=0x0080", 16'h0080, dut.accum[0]);
        check("accum[1]=0x0040", 16'h0040, dut.accum[1]);
 
        // ── TC3: no-fire integration ──────────────────────────────────────
        // V_new[0] = α·0 + 0.5  = 0.5   < 1.0  → no spike
        // V_new[1] = α·0 + 0.25 = 0.25  < 1.0  → no spike
        $display("--- TC3: no-fire integration ---");
        do_capture();
        check("spikes=00 (no fire)", 2'b00,    lif_spikes);
        check("vm[0]=0x0080",        16'h0080, dut.vm[0]);
        check("vm[1]=0x0040",        16'h0040, dut.vm[1]);
 
        // ── TC4: fire + hard reset ────────────────────────────────────────
        // Push neuron 0 over threshold: accum=0xC0 (0.75)
        // V_new[0] = α·0.5 + 0.75 = 0.4375 + 0.75 = 1.1875 >= 1.0 → FIRE
        //   α·0.5: ALPHA=0xE0, vm=0x80 → 0xE0*0x80 = 0x7000 (Q16.16)
        //          bits[23:8] = 0x0070 → 0.4375 ✓
        //   0x0070 + 0x00C0 = 0x0130 >= 0x0100 → fire, vm→0
        // Neuron 1: accum=0x00, V_new[1] = α·0.25 + 0 = 0.21875
        //   α·0.25: 0xE0*0x40 = 0x3800 → bits[23:8] = 0x0038 → 0.21875 ✓
        $display("--- TC4: fire + hard reset ---");
        write_accum(0, 16'h00C0);   // 0.75
        write_accum(1, 16'h0000);   // 0
        do_capture();
        check("spikes=01 (n0 fires)", 2'b01,    lif_spikes);
        check("vm[0]=0 (hard reset)", 16'h0000, dut.vm[0]);
        check("vm[1]=0x0038 (decay)", 16'h0038, dut.vm[1]);
 
        // ── TC5: leak with zero input ─────────────────────────────────────
        // V_new[0] = α·0 + 0 = 0
        // V_new[1] = α·0x0038 + 0 = 0xE0*0x38 → Q16.16 = 0x3100 → [23:8]=0x0031
        // 0x38=56, 0xE0=224, 56*224=12544=0x3100, bits[23:8]=0x0031 ✓
        $display("--- TC5: leak (zero input) ---");
        write_accum(0, 16'h0000);
        write_accum(1, 16'h0000);
        do_capture();
        check("spikes=00 (no fire)", 2'b00,    lif_spikes);
        check("vm[0]=0x0000",        16'h0000, dut.vm[0]);
        check("vm[1]=0x0031",        16'h0031, dut.vm[1]);
 
        // ── TC6: state persistence (no capture) ──────────────────────────
        // Write accumulator but do NOT capture; vm should be unchanged.
        $display("--- TC6: state persistence ---");
        write_accum(0, 16'hFFFF);
        @(posedge clk); #1;
        @(posedge clk); #1;
        check("vm[0] unchanged (no cap)", 16'h0000, dut.vm[0]);
        check("vm[1] unchanged (no cap)", 16'h0031, dut.vm[1]);
 
        // ── TC7: clear_state ──────────────────────────────────────────────
        $display("--- TC7: clear_state ---");
        // First build up some state
        write_accum(1, 16'h00FF);
        do_capture();
        // vm[1] should now be nonzero; then clear
        @(negedge clk); clear_state = 1;
        @(posedge clk); #1; clear_state = 0;
        @(posedge clk); #1;
        check("vm[0]=0 after clear", 16'h0000, dut.vm[0]);
        check("vm[1]=0 after clear", 16'h0000, dut.vm[1]);
 
        // ── Summary ───────────────────────────────────────────────────────
        @(posedge clk); #1;
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS COMPLETED - %0d FAILURE(S)", fail_count);
        $finish;
    end
 
    initial begin #200000; $display("[FAIL] TIMEOUT"); $finish; end
endmodule
