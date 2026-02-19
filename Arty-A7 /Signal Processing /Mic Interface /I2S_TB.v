`timescale 1ns / 1ps

module I2S_tb();

reg clk;
reg rst;
reg sd;

wire bclk;
wire lrclk;
wire [15:0] sample;
wire sample_valid;

// Clock generation for BCLK and LRCLK (simulating I2S master)
reg bclk_reg;
reg lrclk_reg;
integer bclk_count;

// Generate BCLK (divide system clock)
// For 16kHz sample rate: BCLK = 512kHz, so period ~1953ns
// With 100MHz clock (10ns period), divide by ~195
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        bclk_reg <= 0;
        bclk_count <= 0;
    end else begin
        if (bclk_count == 97) begin  // 100MHz/512kHz ≈ 195/2 for 50% duty
            bclk_reg <= ~bclk_reg;
            bclk_count <= 0;
        end else begin
            bclk_count <= bclk_count + 1;
        end
    end
end

// Generate LRCLK (divide BCLK by 32 for 16-bit)
// 512kHz / 32 = 16kHz
reg [4:0] lrclk_div;
always @(posedge bclk_reg or negedge rst) begin
    if (!rst) begin
        lrclk_reg <= 0;
        lrclk_div <= 0;
    end else begin
        if (lrclk_div == 31) begin
            lrclk_reg <= ~lrclk_reg;
            lrclk_div <= 0;
        end else begin
            lrclk_div <= lrclk_div + 1;
        end
    end
end

assign bclk = bclk_reg;
assign lrclk = lrclk_reg;

I2S uut (
    .mclk(clk),      // Note: changed from .clk to .mclk to match your module
    .rst_n(rst),     // Note: changed from .rst to .rst_n (active low)
    .sd(sd), 
    .bclk(bclk), 
    .lrclk(lrclk), 
    .audio_sample(sample),  // Note: changed from .sample to .audio_sample
    .sample_valid(sample_valid)
);

// Generate 100MHz clock
initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period = 100MHz
end

integer i;
integer k;
reg [15:0] test_word;  // 16-bit test word

initial begin
    // Initialize
    rst = 0;  // Active low reset - start with reset asserted
    sd = 0;
    test_word = 0;
    
    #100;
    rst = 1;  // Release reset
    
    // Wait for LRCLK to stabilize
    #1000;
    
    // Test multiple words
    for (k = 0; k < 10; k = k + 1) begin
        // Generate random 16-bit test word
        test_word = $random;
        
        $display("Starting transmission of word: %h", test_word);
        
        // Wait for start of left channel (LRCLK low)
        wait(lrclk == 0);
        
        // Send 16 bits MSB first (I2S format)
        for (i = 15; i >= 0; i = i - 1) begin
            @(posedge bclk);  // Wait for rising edge
            sd = test_word[i];
            #1;  // Small delay for setup time
        end
        
        // Wait for sample to be captured
        @(posedge sample_valid);
        #100;  // Allow time for display
        
        // Display result
        $display("Time: %t | Sent: %h | Received: %h | Match: %s", 
                 $time, test_word, sample, 
                 (test_word == sample) ? "PASS" : "FAIL");
    end
    
    // Send some silence (all zeros)
    $display("\n--- Testing silence ---");
    wait(lrclk == 0);
    for (i = 15; i >= 0; i = i - 1) begin
        @(posedge bclk);
        sd = 0;
        #1;
    end
    
    @(posedge sample_valid);
    $display("Time: %t | Sent: 0000 | Received: %h", $time, sample);
    
    // Send max value
    $display("\n--- Testing maximum value ---");
    wait(lrclk == 0);
    for (i = 15; i >= 0; i = i - 1) begin
        @(posedge bclk);
        sd = 1;  // All ones
        #1;
    end
    
    @(posedge sample_valid);
    $display("Time: %t | Sent: FFFF | Received: %h", $time, sample);
    
    #5000;
    $display("\n========================================");
    $display("Simulation Finished.");
    $display("========================================");
    $finish;
end

// Monitor LRCLK and BCLK for debugging
always @(posedge bclk) begin
    // Uncomment for detailed debugging
    // $display("BCLK edge: lrclk=%b, sd=%b, bit_count=%d", lrclk, sd, uut.bit_count);
end

endmodule
