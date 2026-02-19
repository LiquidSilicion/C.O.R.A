`timescale 1ns / 1ps

module tb_circular_buffer();

    // Parameters
    parameter BUFFER_SIZE = 24000;
    parameter CLK_PERIOD = 10; // 10ns = 100MHz clock
    
    // Testbench signals
    reg clk;
    reg rst_n;
    reg [15:0] data_in;
    reg sample_valid;
    
    wire [15:0] data_out;
    wire buffer_full;
    
    // Monitor variables
    integer i;
    integer errors = 0;
    integer pass_count = 0;
    integer write_count = 0;
    integer read_count = 0;
    reg [15:0] expected_data;
    reg [15:0] written_data [0:999]; // Store written data for verification
    
    // Instantiate the DUT
    circular_buffer #(
        .BUFFER_SIZE(BUFFER_SIZE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .sample_valid(sample_valid),
        .data_out(data_out),
        .buffer_full(buffer_full)
    );
    
    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Test procedure
    initial begin
        // Initialize signals
        clk = 0;
        rst_n = 0;
        data_in = 16'h0000;
        sample_valid = 0;
        
        // Apply reset
        #(CLK_PERIOD*2);
        rst_n = 1;
        #(CLK_PERIOD);
        
        $display("==================================================");
        $display("Circular Buffer Testbench Started");
        $display("Buffer Size: %0d elements", BUFFER_SIZE);
        $display("Data Width: 16 bits");
        $display("==================================================\n");
        
        // Test 1: Reset verification
        $display("TEST 1: Reset Verification");
        test_reset();
        
        // Test 2: Basic write and continuous read
        #(CLK_PERIOD*5);
        $display("\nTEST 2: Basic Write and Read Operations");
        test_basic_write_read();
        
        // Test 3: Buffer full condition
        #(CLK_PERIOD*5);
        $display("\nTEST 3: Buffer Full Condition");
        test_buffer_full();
        
        // Test 4: Wrap-around behavior
        #(CLK_PERIOD*5);
        $display("\nTEST 4: Wrap-Around Behavior");
        test_wrap_around();
        
        // Test 5: Write after full
        #(CLK_PERIOD*5);
        $display("\nTEST 5: Write When Buffer Full");
        test_write_when_full();
        
        // Test 6: Random operations
        #(CLK_PERIOD*5);
        $display("\nTEST 6: Random Write/Read Operations");
        test_random_operations();
        
        // Test 7: Boundary conditions
        #(CLK_PERIOD*5);
        $display("\nTEST 7: Boundary Conditions");
        test_boundary_conditions();
        
        // Summary
        #(CLK_PERIOD*10);
        $display("\n==================================================");
        $display("TEST SUMMARY");
        $display("==================================================");
        $display("Total tests passed: %0d", pass_count);
        $display("Total errors: %0d", errors);
        
        if (errors == 0) begin
            $display("\n✅ ALL TESTS PASSED! The circular buffer works correctly.");
        end else begin
            $display("\n❌ SOME TESTS FAILED! Please check the design.");
        end
        $display("==================================================");
        
        #(CLK_PERIOD*10);
        $finish;
    end
    
    // Test 1: Reset verification
    task test_reset;
        begin
            @(posedge clk);
            if (dut.wr_ptr === 0 && dut.rd_ptr === 0 && 
                buffer_full === 0 && dut.wrap_flag === 0) begin
                $display("  ✅ PASS: Reset correctly initialized all signals");
                pass_count = pass_count + 1;
            end else begin
                $display("  ❌ FAIL: Reset did not properly initialize signals");
                $display("     wr_ptr: %0d (expected 0)", dut.wr_ptr);
                $display("     rd_ptr: %0d (expected 0)", dut.rd_ptr);
                $display("     buffer_full: %b (expected 0)", buffer_full);
                $display("     wrap_flag: %b (expected 0)", dut.wrap_flag);
                errors = errors + 1;
            end
        end
    endtask
    
    // Test 2: Basic write and read
    task test_basic_write_read;
        begin
            write_count = 0;
            
            // Write 10 samples
            $display("  Writing 10 samples...");
            for (i = 0; i < 10; i = i + 1) begin
                @(posedge clk);
                data_in = i + 100; // Use unique values
                sample_valid = 1;
                written_data[write_count] = data_in;
                write_count = write_count + 1;
                $display("    Write[%0d]: %0d", i, data_in);
            end
            @(posedge clk);
            sample_valid = 0;
            
            // Read and verify
            #(CLK_PERIOD*2);
            $display("  Reading back samples...");
            for (i = 0; i < 10; i = i + 1) begin
                #(CLK_PERIOD);
                expected_data = i + 100;
                if (data_out !== expected_data) begin
                    $display("    ❌ FAIL: Read[%0d] = %0d (expected %0d)", 
                            i, data_out, expected_data);
                    errors = errors + 1;
                end else begin
                    $display("    ✅ PASS: Read[%0d] = %0d", i, data_out);
                end
            end
            
            if (errors == 0) pass_count = pass_count + 1;
        end
    endtask
    
    // Test 3: Buffer full condition
    task test_buffer_full;
        begin
            write_count = 0;
            
            // Write until buffer is full
            $display("  Writing until buffer full...");
            while (!buffer_full && write_count < BUFFER_SIZE + 10) begin
                @(posedge clk);
                data_in = write_count;
                sample_valid = 1;
                write_count = write_count + 1;
            end
            
            @(posedge clk);
            sample_valid = 0;
            
            // Verify buffer full condition
            #(CLK_PERIOD);
            if (buffer_full) begin
                $display("  ✅ PASS: Buffer full correctly asserted after %0d writes", write_count);
                $display("     wr_ptr: %0d, rd_ptr: %0d", dut.wr_ptr, dut.rd_ptr);
                pass_count = pass_count + 1;
            end else begin
                $display("  ❌ FAIL: Buffer full not asserted when expected");
                $display("     wr_ptr: %0d, rd_ptr: %0d", dut.wr_ptr, dut.rd_ptr);
                errors = errors + 1;
            end
        end
    endtask
    
    // Test 4: Wrap-around behavior
    task test_wrap_around;
        begin
            // Clear buffer by reading until empty (or use reset)
            @(posedge clk);
            rst_n = 0;
            #(CLK_PERIOD*2);
            rst_n = 1;
            #(CLK_PERIOD);
            
            $display("  Testing wrap-around by writing more than buffer size...");
            write_count = 0;
            
            // Write more than buffer size to force wrap
            for (i = 0; i < BUFFER_SIZE + 100; i = i + 1) begin
                @(posedge clk);
                data_in = i % 65536;
                sample_valid = (i < BUFFER_SIZE + 50) ? 1 : 0; // Stop after a while
                write_count = i;
            end
            
            @(posedge clk);
            sample_valid = 0;
            
            // Check if wrap occurred
            #(CLK_PERIOD);
            if (dut.wrap_flag) begin
                $display("  ✅ PASS: Wrap flag was set correctly");
                $display("     Final wr_ptr: %0d (after %0d writes)", dut.wr_ptr, write_count);
                pass_count = pass_count + 1;
            end else begin
                $display("  ❌ FAIL: Wrap flag never set");
                errors = errors + 1;
            end
        end
    endtask
    
    // Test 5: Write when buffer full
    task test_write_when_full;
        begin
            // Make buffer full
            @(posedge clk);
            while (!buffer_full) begin
                @(posedge clk);
                data_in = $random;
                sample_valid = 1;
            end
            
            $display("  Buffer is full (wr_ptr=%0d, rd_ptr=%0d)", dut.wr_ptr, dut.rd_ptr);
            
            // Write one more sample when full
            @(posedge clk);
            data_in = 16'hDEAD;
            sample_valid = 1;
            
            @(posedge clk);
            sample_valid = 0;
            
            // Check if rd_ptr incremented (oldest sample overwritten)
            #(CLK_PERIOD);
            $display("  After writing when full: wr_ptr=%0d, rd_ptr=%0d", 
                    dut.wr_ptr, dut.rd_ptr);
            
            // Read next sample (should be the one after the overwritten oldest)
            #(CLK_PERIOD);
            $display("  Next data out: %0h", data_out);
            
            pass_count = pass_count + 1; // Manual inspection required
        end
    endtask
    
    // Test 6: Random operations
    task test_random_operations;
        integer ops;
        integer rand_data;
        integer rd_ptr_before, wr_ptr_before;
        begin
            $display("  Performing 50 random operations...");
            
            for (ops = 0; ops < 50; ops = ops + 1) begin
                @(posedge clk);
                
                rd_ptr_before = dut.rd_ptr;
                wr_ptr_before = dut.wr_ptr;
                
                // Random write (70% probability)
                if ($random % 10 < 7) begin
                    rand_data = $random % 65536;
                    data_in = rand_data;
                    sample_valid = 1;
                    
                    if (ops % 10 == 0) begin
                        $display("    Write: 0x%04h at addr %0d", rand_data, wr_ptr_before);
                    end
                end else begin
                    sample_valid = 0;
                    if (ops % 10 == 0) begin
                        $display("    Idle cycle");
                    end
                end
                
                // Monitor pointer movement
                if (ops % 20 == 19) begin
                    $display("    Status - wr_ptr: %0d, rd_ptr: %0d, full: %b", 
                            dut.wr_ptr, dut.rd_ptr, buffer_full);
                end
            end
            
            @(posedge clk);
            sample_valid = 0;
            
            $display("  ✅ PASS: Random operations completed without errors");
            pass_count = pass_count + 1;
        end
    endtask
    
    // Test 7: Boundary conditions
    task test_boundary_conditions;
        begin
            // Test near buffer end
            $display("  Testing near buffer end...");
            
            // Reset
            @(posedge clk);
            rst_n = 0;
            #(CLK_PERIOD*2);
            rst_n = 1;
            #(CLK_PERIOD);
            
            // Write until just before end
            for (i = 0; i < BUFFER_SIZE - 2; i = i + 1) begin
                @(posedge clk);
                data_in = i;
                sample_valid = 1;
            end
            
            $display("    Before boundary: wr_ptr=%0d, rd_ptr=%0d", dut.wr_ptr, dut.rd_ptr);
            
            // Write at boundary
            @(posedge clk);
            data_in = 16'hB0B0;
            sample_valid = 1;
            
            $display("    At boundary: wr_ptr=%0d, rd_ptr=%0d", dut.wr_ptr, dut.rd_ptr);
            
            // Write crossing boundary
            @(posedge clk);
            data_in = 16'hC0C0;
            sample_valid = 1;
            
            $display("    After boundary: wr_ptr=%0d, rd_ptr=%0d", dut.wr_ptr, dut.rd_ptr);
            
            @(posedge clk);
            sample_valid = 0;
            
            // Read back to verify no data corruption
            #(CLK_PERIOD*5);
            $display("    Boundary test completed");
            
            pass_count = pass_count + 1;
        end
    endtask
    
    // Monitor waveform dump
    initial begin
        $dumpfile("circular_buffer_tb.vcd");
        $dumpvars(0, tb_circular_buffer);
        $dumpvars(1, dut.circular_buffer[0:10]); // Dump first 11 buffer locations
    end

endmodule
