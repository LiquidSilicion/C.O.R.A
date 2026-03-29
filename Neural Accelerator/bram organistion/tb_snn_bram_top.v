`timescale 1ns/1ps

module tb_snn_bram_top;

reg         clka = 0, clkb = 0;
reg         ena, enb, wea;
reg  [16:0] addr;
reg  [31:0] din;
wire [31:0] dout;
reg         ena_wide, enb_wide, wea_wide;
reg  [8:0]  addr_wide;
reg  [127:0] din_wide;
wire [127:0] dout_wide;

snn_bram_top dut (
    .clka(clka), .clkb(clkb),
    .ena(ena), .enb(enb), .wea(wea),
    .addr(addr), .din(din), .dout(dout),
    .ena_wide(ena_wide), .enb_wide(enb_wide), .wea_wide(wea_wide),
    .addr_wide(addr_wide), .din_wide(din_wide), .dout_wide(dout_wide)
);

always #5 clka = ~clka;
always #5 clkb = ~clkb;

task write32;
    input [16:0] a; input [31:0] d;
    begin
        @(posedge clka); ena=1; wea=1; addr=a; din=d;
        @(posedge clka); ena=0; wea=0;
    end
endtask

task read32;
    input [16:0] a; input [31:0] expected;
    begin
        @(posedge clkb); enb=1; addr=a;
        @(posedge clkb); @(posedge clkb); enb=0;
        if (dout===expected) $display("PASS  addr=0x%05h  got=0x%08h",a,dout);
        else $display("FAIL  addr=0x%05h  got=0x%08h  exp=0x%08h",a,dout,expected);
    end
endtask

// KEY FIX: write128/read128 now take the full 17-bit address
// so sel_b1_s and sel_b2_spk fire correctly via addr
task write128;
    input [16:0] a; input [8:0] aw; input [127:0] d;
    begin
        @(posedge clka);
        addr=a; ena_wide=1; wea_wide=1; addr_wide=aw; din_wide=d;
        @(posedge clka);
        ena_wide=0; wea_wide=0;
    end
endtask

task read128;
    input [16:0] a; input [8:0] aw; input [127:0] expected;
    begin
        @(posedge clkb);
        addr=a; enb_wide=1; addr_wide=aw;
        @(posedge clkb); @(posedge clkb); enb_wide=0;
        if (dout_wide===expected)
            $display("PASS  addr=0x%05h  got=0x%032h",a,dout_wide);
        else
            $display("FAIL  addr=0x%05h  got=0x%032h  exp=0x%032h",a,dout_wide,expected);
    end
endtask

initial begin
    ena=0;enb=0;wea=0;addr=0;din=0;
    ena_wide=0;enb_wide=0;wea_wide=0;addr_wide=0;din_wide=0;
    #40;

    $display("=== Bank 0: Config ===");
    write32(17'h00000, 32'hA5A50102); write32(17'h00001, 32'h12345678);
    read32 (17'h00000, 32'hA5A50102); read32 (17'h00001, 32'h12345678);

    $display("=== Bank 1a: V_m ===");
    write32(17'h01000, 32'h0000FFFF); write32(17'h01001, 32'h0000ABCD);
    read32 (17'h01000, 32'h0000FFFF); read32 (17'h01001, 32'h0000ABCD);

    $display("=== Bank 1b: S[t] 128-bit ===");
    write128(17'h02000, 9'h000, 128'hDEADBEEFCAFEBABE123456789ABCDEF0);
    read128 (17'h02000, 9'h000, 128'hDEADBEEFCAFEBABE123456789ABCDEF0);

    $display("=== Bank 1c: X[t] ===");
    write32(17'h02800, 32'h00001111); read32(17'h02800, 32'h00001111);

    $display("=== Bank 1d: y[t] ===");
    write32(17'h02C00, 32'h000003FF); read32(17'h02C00, 32'h000003FF);

    $display("=== Bank 2a: Target spikes 128-bit ===");
    write128(17'h03000, 9'h000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    read128 (17'h03000, 9'h000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

    $display("=== Bank 2b: Target outputs ===");
    write32(17'h03800, 32'h000001FF); read32(17'h03800, 32'h000001FF);

    $display("=== Bank 3a: W_in ===");
    write32(17'h04000, 32'h00007FFF); read32(17'h04000, 32'h00007FFF);

    $display("=== Bank 3b: W_rec ===");
    write32(17'h04800, 32'h00001234); read32(17'h04800, 32'h00001234);

    $display("=== Bank 3c: W_out ===");
    write32(17'h08000, 32'h00000042); read32(17'h08000, 32'h00000042);

    $display("=== Bank 4a: dW_in ===");
    write32(17'h09000, 32'hFFFF0001); read32(17'h09000, 32'hFFFF0001);

    $display("=== Bank 4b: dW_rec ===");
    write32(17'h09800, 32'h80000000); read32(17'h09800, 32'h80000000);

    $display("=== Bank 4c: dW_out ===");
    write32(17'h0D000, 32'h0000DEAD); read32(17'h0D000, 32'h0000DEAD);

    $display("=== Bank 5: Neuron states ===");
    write32(17'h0E000, 32'h000003C0); write32(17'h0E080, 32'h00000100);
    read32 (17'h0E000, 32'h000003C0); read32 (17'h0E080, 32'h00000100);

    $display("=== Unmapped ===");
    read32(17'h0F000, 32'hDEADBEEF);

    $display("=== Done ===");
    #100; $finish;
end

initial begin #1000000; $display("TIMEOUT"); $finish; end

endmodule
