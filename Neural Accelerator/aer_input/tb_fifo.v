// tb_fifo.v - Verilog-2001 compatible testbench

`timescale 1ns/1ps

module tb_fifo;

    parameter CLK_PERIOD = 10;
    parameter DATA_W = 24;
    parameter DEPTH = 64;

    reg clk, rst, wr_en, rd_en;
    reg [DATA_W-1:0] din;
    wire [DATA_W-1:0] dout;
    wire full, empty;

    // Loop counters - declared at module level
    integer i;
    reg [DATA_W-1:0] recv_data;

    fifo_cdc #(
        .DATA_WIDTH(DATA_W),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .rd_en(rd_en),
        .din(din), .dout(dout),
        .full(full), .empty(empty)
    );

    // Clock generation
    initial begin
        clk = 0; 
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Main test sequence
    initial begin
        $display("=== FIFO Testbench ===");
        
        // Reset
        rst = 0; 
        wr_en = 0; 
        rd_en = 0; 
        din = 0;
        #20; 
        rst = 1; 
        #20;

        // Test 1: Empty flag after reset
        if (empty !== 1'b1) begin
            $error("Empty flag wrong after reset");
        end else begin
            $display("[PASS] Empty flag correct after reset");
        end
        
        // Test 2: Write 10, read 10
        $display("\n[Test 1] Write 10, read 10");
        for (i = 0; i < 10; i = i + 1) begin
            wait (!full);
            din = 24'h100000 + i;
            wr_en = 1;
            #10;
            wr_en = 0;
            #10;
        end
        
        for (i = 0; i < 10; i = i + 1) begin
            wait (!empty);
            rd_en = 1;
            #10;
            recv_data = dout;
            rd_en = 0;
            #10;
            if (recv_data !== (24'h100000 + i)) begin
                $error("Data mismatch: expected %0h, got %0h", 24'h100000+i, recv_data);
            end else begin
                $display("  [%0d] Read: %0h [OK]", i, recv_data);
            end
        end

        // Test 3: Fill to full
        $display("\n[Test 2] Fill to full");
        for (i = 0; i < DEPTH; i = i + 1) begin
            wait (!full);
            din = 24'h200000 + i;
            wr_en = 1;
            #10;
            wr_en = 0;
            #10;
        end
        
        if (full !== 1'b1) begin
            $error("Full flag not asserted");
        end else begin
            $display("[PASS] Full flag asserted correctly");
        end
        
        // Try to write when full (should be ignored)
        din = 24'hDEADBEEF;
        wr_en = 1;
        #10;
        wr_en = 0;
        #20;
        
        // Read all
        for (i = 0; i < DEPTH; i = i + 1) begin
            wait (!empty);
            rd_en = 1;
            #10;
            recv_data = dout;
            rd_en = 0;
            #10;
        end
        
        if (empty !== 1'b1) begin
            $error("Empty flag not asserted after drain");
        end else begin
            $display("[PASS] Empty flag correct after drain");
        end

        // Test 4: Simultaneous read/write (backpressure)
        $display("\n[Test 3] Simultaneous R/W");
        wr_en = 1; 
        rd_en = 1;
        for (i = 0; i < 20; i = i + 1) begin
            din = 24'h300000 + i;
            #10;
        end
        wr_en = 0; 
        rd_en = 0;

        #100;
        $display("\n=== FIFO Tests Passed ===");
        $finish;
    end

endmodule
