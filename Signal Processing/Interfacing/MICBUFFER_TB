`timescale 1ns/1ps

module fifo_tb;

  reg clk;
  reg rst;
  reg rd_en;
  reg wr_en;
  reg [15:0] din;

  wire [15:0] dout;
  wire full;
  wire empty;

  integer i;
  integer errors;

  // DUT
  fifo dut (
    .clk(clk),
    .rst(rst),
    .rd_en(rd_en),
    .wr_en(wr_en),
    .din(din),
    .dout(dout),
    .full(full),
    .empty(empty)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    errors = 0;
    rd_en  = 0;
    wr_en  = 0;
    din    = 0;

 
    rst = 0;
    repeat(5) @(posedge clk);
    rst = 1;
    repeat(2) @(posedge clk);


    $display("---- Writing 128 values ----");

    for (i = 0; i < 128; i = i + 1) begin
      @(posedge clk);
      if (!full) begin
        wr_en <= 1;
        din   <= i;
      end
      else begin
        $display("ERROR: FIFO became full too early at i=%0d", i);
        errors = errors + 1;
      end
    end

    @(posedge clk);
    wr_en <= 0;

    @(posedge clk);
    if (!full) begin
      $display("ERROR: FIFO not FULL after 128 writes");
      errors = errors + 1;
    end
    else
      $display("FIFO FULL asserted correctly");

    $display("---- Reading 128 values ----");

    for (i = 0; i < 128; i = i + 1) begin
      @(posedge clk);
      rd_en <= 1;

      // Because read is synchronous,
      // data appears next clock
      @(posedge clk);

      if (dout !== i) begin
        $display("ERROR: index=%0d expected=%0d got=%0d",
                 i, i, dout);
        errors = errors + 1;
      end
    end

    rd_en <= 0;

    @(posedge clk);
    if (!empty) begin
      $display("ERROR: FIFO not EMPTY after 128 reads");
      errors = errors + 1;
    end
    else
      $display("FIFO EMPTY asserted correctly");

 
    if (errors == 0)
      $display("TEST PASSED ✅");
    else
      $display("TEST FAILED ❌  Errors = %0d", errors);

    repeat(5) @(posedge clk);
    $finish;
  end

endmodule
