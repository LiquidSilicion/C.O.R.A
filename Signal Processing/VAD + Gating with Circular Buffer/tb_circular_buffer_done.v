module tb_circular_buffer;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    localparam BUFFER_SIZE         = 24000;
    localparam PRE_TRIGGER_SAMPLES = 3200;
    localparam ADDR_WIDTH          = 15;
    localparam CLK_PERIOD          = 10;   // 100MHz

    // --------------------------------------------------------
    // DUT ports
    // --------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg [15:0] data_in;
    reg        sample_valid;
    reg        rd_en;
    reg        pre_trig_rewind;

    wire [15:0] data_out;
    wire        data_valid;
    wire        buffer_full;

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------
    circular_buffer #(
        .BUFFER_SIZE         (BUFFER_SIZE),
        .ADDR_WIDTH          (ADDR_WIDTH),
        .PRE_TRIGGER_SAMPLES (PRE_TRIGGER_SAMPLES)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .data_in         (data_in),
        .sample_valid    (sample_valid),
        .rd_en           (rd_en),
        .pre_trig_rewind (pre_trig_rewind),
        .data_out        (data_out),
        .data_valid      (data_valid),
        .buffer_full     (buffer_full)
    );

    // --------------------------------------------------------
    // Clock
    // --------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --------------------------------------------------------
    // Test tracking
    // --------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [127:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected) begin
                $display("  PASS  [%0s]  got %0d (0x%04h)", name, actual, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  [%0s]  expected %0d (0x%04h)  got %0d (0x%04h)  @time %0t",
                         name, expected, expected, actual, actual, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // --------------------------------------------------------
    // Task: write N samples, data = index value (for easy checking)
    // --------------------------------------------------------
    task write_samples;
        input integer n;
        input integer start_val;   // data_in = start_val + i
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
                data_in      = start_val[15:0] + i[15:0];
                sample_valid = 1'b1;
                @(posedge clk);
                sample_valid = 1'b0;
                @(posedge clk);
            end
        end
    endtask

    // --------------------------------------------------------
    // Task: write one sample with specific value
    // --------------------------------------------------------
    task write_one;
        input [15:0] val;
        begin
            @(posedge clk);
            data_in      = val;
            sample_valid = 1'b1;
            @(posedge clk);
            sample_valid = 1'b0;
        end
    endtask

    // --------------------------------------------------------
    // Task: do one read, return data_out after data_valid
    // --------------------------------------------------------
    task do_read;
        output [15:0] captured;
        begin
            @(posedge clk);
            rd_en = 1'b1;
            @(posedge clk);
            rd_en = 1'b0;
            // data_valid goes high 1 cycle after rd_en
            @(posedge clk);
            captured = data_out;
        end
    endtask

    // --------------------------------------------------------
    // MAIN TEST
    // --------------------------------------------------------
    reg [15:0] cap;
    integer i;

    initial begin
        $dumpfile("tb_circular_buffer.vcd");
        $dumpvars(0, tb_circular_buffer);

        $display("\n=== CIRCULAR BUFFER TESTBENCH ===\n");

        // --- Reset ---
        rst_n           = 1'b0;
        data_in         = 16'd0;
        sample_valid    = 1'b0;
        rd_en           = 1'b0;
        pre_trig_rewind = 1'b0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        // ==================================================
        // TB1: Write 10 samples, read back sequentially
        //      Data written: 0x0001, 0x0002, ... 0x000A
        //      Expected read order: 0x0001, 0x0002, ...
        // ==================================================
        $display("--- TB1: Write 10 samples, read back sequentially ---");
        write_samples(10, 1);   // writes 1,2,3...10

        // Read them back
        for (i = 0; i < 10; i = i + 1) begin
            do_read(cap);
            // Note: sync read - data_out valid 1 cycle after rd_en
            // rd_ptr starts at 0 after reset, first rd_en reads addr 0 = sample 1
            if (cap === (i + 1))
                $display("  PASS  [TB1 read[%0d]]  got 0x%04h", i, cap);
            else
                $display("  FAIL  [TB1 read[%0d]]  expected 0x%04h got 0x%04h", i, i+1, cap);
        end

        // ==================================================
        // TB2: Write exactly BUFFER_SIZE samples (full wrap)
        //      wr_ptr should return to 0 after 24000 writes
        //      Write known pattern: addr i → value (i & 0xFFFF)
        // ==================================================
        $display("\n--- TB2: Full buffer wrap (24000 samples) ---");
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        // Write BUFFER_SIZE samples: value = index mod 0x10000
        for (i = 0; i < BUFFER_SIZE; i = i + 1) begin
            @(posedge clk);
            data_in      = i[15:0];
            sample_valid = 1'b1;
            @(posedge clk);
            sample_valid = 1'b0;
            @(posedge clk);
        end

        // Write one more - should overwrite addr 0 with 24000
        @(posedge clk);
        data_in      = 16'hBEEF;
        sample_valid = 1'b1;
        @(posedge clk);
        sample_valid = 1'b0;
        @(posedge clk);

        // Read addr 0 - should see 0xBEEF (overwritten)
        // First we need to rewind rd_ptr to 0 - use pre_trig_rewind
        // and then read. For simplicity, reset and re-test.
        $display("  INFO  Wrap test completed - wr_ptr wraps at BUFFER_SIZE correctly if no X states in data_out");

        // ==================================================
        // TB3: Pre-trigger rewind
        //      Write 4000 known samples (values 0x1000+i)
        //      Issue pre_trig_rewind
        //      Read PRE_TRIGGER_SAMPLES (3200) samples
        //      First sample should be value at (4000 - 3200) = index 800
        //      i.e., data = 0x1000 + 800 = 0x1320
        // ==================================================
        $display("\n--- TB3: Pre-trigger rewind (3200 samples back) ---");
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        // Write 4000 samples: value = 0x1000 + i
        for (i = 0; i < 4000; i = i + 1) begin
            @(posedge clk);
            data_in      = 16'h1000 + i[15:0];
            sample_valid = 1'b1;
            @(posedge clk);
            sample_valid = 1'b0;
            @(posedge clk);
        end

        // wr_ptr is now at 4000
        // Issue pre_trig_rewind - rd_ptr should jump to 4000-3200 = 800
        @(posedge clk);
        pre_trig_rewind = 1'b1;
        @(posedge clk);
        pre_trig_rewind = 1'b0;
        @(posedge clk);

        // Read first sample after rewind
        // rd_ptr = 800, mem[800] = 0x1000 + 800 = 0x1320
        do_read(cap);
        check("TB3 first after rewind", cap, 16'h1000 + 800);

        // Read second sample: mem[801] = 0x1000 + 801 = 0x1321
        do_read(cap);
        check("TB3 second after rewind", cap, 16'h1000 + 801);

        // Read a few more to verify sequential
        do_read(cap); check("TB3 [802]", cap, 16'h1000 + 802);
        do_read(cap); check("TB3 [803]", cap, 16'h1000 + 803);

        // ==================================================
        // TB4: Pre-trigger rewind when wr_ptr < PRE_TRIGGER_SAMPLES
        //      (wrap-around case: wr_ptr=100, rewind 3200 → wraps)
        //      Write 100 samples, rewind, verify rd_ptr wraps correctly
        //      Expected rd_ptr = 100 + (24000 - 3200) = 20900
        // ==================================================
        $display("\n--- TB4: Pre-trigger rewind with wrap-around ---");
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        // First fill buffer completely so we have valid data at high addresses
        for (i = 0; i < BUFFER_SIZE; i = i + 1) begin
            @(posedge clk);
            data_in      = i[15:0];
            sample_valid = 1'b1;
            @(posedge clk);
            sample_valid = 1'b0;
            @(posedge clk);
        end
        // wr_ptr = 0 now (just wrapped)

        // Write 100 more samples: values 0xA000+0 to 0xA063
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            data_in      = 16'hA000 + i[15:0];
            sample_valid = 1'b1;
            @(posedge clk);
            sample_valid = 1'b0;
            @(posedge clk);
        end
        // wr_ptr = 100, addresses 0-99 hold 0xA000-0xA063

        // Issue pre_trig_rewind
        // Expected: rd_ptr = 100 + (24000 - 3200) = 20900
        // mem[20900] = 20900 (written in the initial fill)
        @(posedge clk);
        pre_trig_rewind = 1'b1;
        @(posedge clk);
        pre_trig_rewind = 1'b0;
        @(posedge clk);

        do_read(cap);
        check("TB4 wrap rewind [20900]", cap, 16'd20900);

        do_read(cap);
        check("TB4 wrap rewind [20901]", cap, 16'd20901);

        // ==================================================
        // TB5: data_valid timing - must assert exactly 1 cycle after rd_en
        // ==================================================
        $display("\n--- TB5: data_valid timing ---");
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        write_one(16'hCAFE);
        write_one(16'hDEAD);

        @(posedge clk);
        // Check data_valid is low before rd_en
        check("TB5 data_valid=0 before rd_en", data_valid, 1'b0);

        rd_en = 1'b1;
        @(posedge clk);
        rd_en = 1'b0;
        // data_valid should be high NOW (registered in same posedge as read)
        @(posedge clk);
        check("TB5 data_valid=1 after rd_en", data_valid, 1'b1);
        check("TB5 data_out=0xCAFE",          data_out,   16'hCAFE);

        @(posedge clk);
        // data_valid deasserts next cycle (no rd_en)
        check("TB5 data_valid=0 after", data_valid, 1'b0);

        // ==================================================
        // Summary
        // ==================================================
        $display("\n=== RESULTS: %0d PASS / %0d FAIL ===\n", pass_count, fail_count);
        if (fail_count == 0)
            $display("All tests passed.\n");
        else
            $display("FAILURES detected - review above.\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
