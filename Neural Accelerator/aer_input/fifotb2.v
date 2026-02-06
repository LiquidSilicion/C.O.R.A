module fifotb();
  reg clk;
  reg rst;
  reg rd_en;
  reg wr_en;
  reg [23:0] din;
  wire [23:0] dout;
  wire full;
  wire empty;
  
  integer i;
  
  fifo dut(
    .clk(clk),
    .rst(rst),
    .rd_en(rd_en),
    .wr_en(wr_en),
    .din(din),
    .dout(dout),
    .full(full),
    .empty(empty)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
 
  initial begin
    // Initialize all signals
    rst = 0;
    wr_en = 0;
    rd_en = 0;
    din = 0;
    
    // Apply reset
    #10;
    rst = 1;
    #10;
    
    wr_en = 1;
    for (i = 0; i < 100; i = i + 1) begin
      din = i + 1000;  // Simple pattern
      #10;
      if (full) begin
        break;
      end
    end
    wr_en = 0;
    #20;
    
    rd_en = 1;
    while (!empty) begin
      #10;
    end
    rd_en = 0;
    #20;
    
    fork
      begin  // Write thread
        wr_en = 1;
        for (i = 0; i < 30; i = i + 1) begin
          din = i + 2000;
          #10;
        end
        wr_en = 0;
      end
      begin  // Read thread (start with delay)
        #50;
        rd_en = 1;
        repeat(20) #10;
        rd_en = 0;
      end
    join
    
    wr_en = 0;
    rd_en = 1;
    #30;
    rd_en = 0;
    
    wr_en = 1;
    rd_en = 0;
    for (i = 0; i < 70; i = i + 1) begin
      din = i + 3000;
      #10;
      if (full) begin
        #10;
        din = 24'h000fff;  // This should not be written
        #10;
        break;
      end
    end
    wr_en = 0;
    
    #100;
  end
  
endmodule
