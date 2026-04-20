`timescale 1ns / 1ps

module tb_uart;

    // Testbench parameters
    localparam CLK_PERIOD = 10; // 100MHz = 10ns period
    
    // Signals to connect to DUT
    reg  clk_100MHz;
    reg  rst_n;
    reg  window_done;
    reg  [3:0] cmd_id;
    reg  [16:0] final_score;
    wire uart_tx;
    wire tx_busy;
    
    // Instantiate the CORA top module
    cora_top dut (
        .clk_100MHz(clk_100MHz),
        .rst_n(rst_n),
        .window_done(window_done),
        .cmd_id(cmd_id),
        .final_score(final_score),
        .uart_tx(uart_tx),
        .tx_busy(tx_busy)
    );
    
    // Clock generation - THIS WAS MISSING!
    initial begin
        clk_100MHz = 0;
        forever #(CLK_PERIOD/2) clk_100MHz = ~clk_100MHz;
    end
    
    // UART Monitor Task
    task automatic monitor_uart;
        integer i;
        reg [7:0] rx_byte;
        begin
            // Wait for start bit
            wait(uart_tx == 0);
            #4340; // Half bit time (8680ns/2)
            
            // Sample 8 bits
            rx_byte = 0;
            for (i = 0; i < 8; i = i + 1) begin
                #8680; // One bit time at 115200 baud
                rx_byte[i] = uart_tx;
            end
            #8680; // Stop bit
            
            $display("  UART RX: 0x%02h ('%c')", rx_byte, rx_byte);
        end
    endtask
    
    // Main stimulus
    initial begin
        $display("=== CORA UART Testbench ===\n");
        
        // Initialize all signals
        rst_n = 0;
        window_done = 0;
        cmd_id = 4'd0;
        final_score = 17'd0;
        
        // Hold reset for 100ns
        #100;
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        
        // Wait for system to stabilize
        #1000;
        
        // Test 1: CMD=3, Score=8700 → 87% confidence
        $display("\n[%0t] Test 1: CMD=3, Score=8700 (expect 87%%)", $time);
        cmd_id = 4'd3;
        final_score = 17'd8700;
        window_done = 1;
        #10;
        window_done = 0;
        
        // Wait for UART transmission
        #50000;
        
        // Test 2: CMD=9, Score=10000 → 100% confidence
        $display("\n[%0t] Test 2: CMD=9, Score=10000 (expect 100%%)", $time);
        cmd_id = 4'd9;
        final_score = 17'd10000;
        window_done = 1;
        #10;
        window_done = 0;
        
        // Wait for UART transmission
        #50000;
        
        // Test 3: CMD=0, Score=4200 → 42% confidence
        $display("\n[%0t] Test 3: CMD=0, Score=4200 (expect 42%%)", $time);
        cmd_id = 4'd0;
        final_score = 17'd4200;
        window_done = 1;
        #10;
        window_done = 0;
        
        // Wait for UART transmission
        #50000;
        
        $display("\n[%0t] === All Tests Complete ===", $time);
        $finish;
    end
    
    // Optional: Monitor signal changes
    always @(posedge uart_tx or negedge uart_tx) begin
        $display("[%0t] uart_tx changed to %b", $time, uart_tx);
    end
    
    always @(posedge tx_busy) begin
        $display("[%0t] tx_busy asserted", $time);
    end

endmodule
