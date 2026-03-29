`timescale 1ns/1ps

module snn_bram_top (
    input  wire         clka,
    input  wire         clkb,

    // Narrow bus (32-bit max) - used for all banks except spike trains
    input  wire         ena,
    input  wire         enb,
    input  wire         wea,
    input  wire [16:0]  addr,
    input  wire [31:0]  din,
    output reg  [31:0]  dout,

    // Wide bus (128-bit) - used only for spike train banks
    input  wire         ena_wide,
    input  wire         enb_wide,
    input  wire         wea_wide,
    input  wire [8:0]   addr_wide,
    input  wire [127:0] din_wide,
    output reg  [127:0] dout_wide
);

ila_0 your_instance_name (
	.clk(clka), // input wire clk


	.probe0(addr), // input wire [16:0]  probe0  
	.probe1(din), // input wire [31:0]  probe1 
	.probe2(dout), // input wire [31:0]  probe2 
	.probe3(wea), // input wire [0:0]  probe3 
	.probe4(ena) // input wire [0:0]  probe4
);
// ============================================================
// ADDRESS DECODE
// ============================================================
wire sel_b0       = (addr >= 17'h00000 && addr <= 17'h00FFF);
wire sel_b1_vm    = (addr >= 17'h01000 && addr <= 17'h01FFF);
wire sel_b1_s     = (addr >= 17'h02000 && addr <= 17'h027FF);
wire sel_b1_x     = (addr >= 17'h02800 && addr <= 17'h02BFF);
wire sel_b1_y     = (addr >= 17'h02C00 && addr <= 17'h02FFF);
wire sel_b2_spk   = (addr >= 17'h03000 && addr <= 17'h037FF);
wire sel_b2_out   = (addr >= 17'h03800 && addr <= 17'h03FFF);
wire sel_b3_win   = (addr >= 17'h04000 && addr <= 17'h047FF);
wire sel_b3_wrec  = (addr >= 17'h04800 && addr <= 17'h07FFF);
wire sel_b3_wout  = (addr >= 17'h08000 && addr <= 17'h083FF);
wire sel_b4_dwin  = (addr >= 17'h09000 && addr <= 17'h097FF);
wire sel_b4_dwrec = (addr >= 17'h09800 && addr <= 17'h0CFFF);
wire sel_b4_dwout = (addr >= 17'h0D000 && addr <= 17'h0D3FF);
wire sel_b5       = (addr >= 17'h0E000 && addr <= 17'h0E3FF);

// ============================================================
// DOUT WIRES
// ============================================================
wire [31:0]  dout_b0;
wire [15:0]  dout_b1_vm;
wire [127:0] dout_b1_s;
wire [15:0]  dout_b1_x;
wire [15:0]  dout_b1_y;
wire [127:0] dout_b2_spk;
wire [15:0]  dout_b2_out;
wire [15:0]  dout_b3_win;
wire [15:0]  dout_b3_wrec;
wire [15:0]  dout_b3_wout;
wire [31:0]  dout_b4_dwin;
wire [31:0]  dout_b4_dwrec;
wire [31:0]  dout_b4_dwout;
wire [15:0]  dout_b5;

// ============================================================
// OUTPUT MUX
// ============================================================
always @(*) begin
    case (1'b1)
        sel_b0:       dout = dout_b0;
        sel_b1_vm:    dout = {16'h0, dout_b1_vm};
        sel_b1_x:     dout = {16'h0, dout_b1_x};
        sel_b1_y:     dout = {16'h0, dout_b1_y};
        sel_b2_out:   dout = {16'h0, dout_b2_out};
        sel_b3_win:   dout = {16'h0, dout_b3_win};
        sel_b3_wrec:  dout = {16'h0, dout_b3_wrec};
        sel_b3_wout:  dout = {16'h0, dout_b3_wout};
        sel_b4_dwin:  dout = dout_b4_dwin;
        sel_b4_dwrec: dout = dout_b4_dwrec;
        sel_b4_dwout: dout = dout_b4_dwout;
        sel_b5:       dout = {16'h0, dout_b5};
        default:      dout = 32'hDEAD_BEEF;
    endcase
end

always @(*) begin
    case (1'b1)
        sel_b1_s:   dout_wide = dout_b1_s;
        sel_b2_spk: dout_wide = dout_b2_spk;
        default:    dout_wide = 128'h0;
    endcase
end

// ============================================================
// IP INSTANTIATIONS
// ============================================================

// Bank 0: Config - 32-bit, depth 1024, addr [9:0]
bank_0 u_bank0 (
    .clka  (clka),
    .ena   (sel_b0 & ena),
    .wea   ({wea}),
    .addra (addr[9:0]),
    .dina  (din[31:0]),
    .clkb  (clkb),
    .enb   (sel_b0 & enb),
    .addrb (addr[9:0]),
    .doutb (dout_b0)
);

// Bank 1a: V_m[t] - 16-bit, depth 4096, addr [11:0]
bank_1_vm u_bank1_vm (
    .clka  (clka),
    .ena   (sel_b1_vm & ena),
    .wea   ({wea}),
    .addra (addr[11:0]),
    .dina  (din[15:0]),
    .clkb  (clkb),
    .enb   (sel_b1_vm & enb),
    .addrb (addr[11:0]),
    .doutb (dout_b1_vm)
);

// Bank 1b: S[t] - 128-bit, depth 512, addr [8:0] (wide bus)
bank_1_s u_bank1_s (
    .clka  (clka),
    .ena   (sel_b1_s & ena_wide),
    .wea   ({wea_wide}),
    .addra (addr_wide),
    .dina  (din_wide),
    .clkb  (clkb),
    .enb   (sel_b1_s & enb_wide),
    .addrb (addr_wide),
    .doutb (dout_b1_s)
);

// Bank 1c: X[t] - 16-bit, depth 512, addr [8:0]
bank_1_x u_bank1_x (
    .clka  (clka),
    .ena   (sel_b1_x & ena),
    .wea   ({wea}),
    .addra (addr[8:0]),
    .dina  (din[15:0]),
    .clkb  (clkb),
    .enb   (sel_b1_x & enb),
    .addrb (addr[8:0]),
    .doutb (dout_b1_x)
);

// Bank 1d: y[t] - 16-bit, depth 512, addr [8:0]
bank_1_y u_bank1_y (
    .clka  (clka),
    .ena   (sel_b1_y & ena),
    .wea   ({wea}),
    .addra (addr[8:0]),
    .dina  (din[15:0]),
    .clkb  (clkb),
    .enb   (sel_b1_y & enb),
    .addrb (addr[8:0]),
    .doutb (dout_b1_y)
);

// Bank 2a: Target spikes - 128-bit, depth 256, addr [7:0] (wide bus)
bank_2_spk u_bank2_spk (
    .clka  (clka),
    .ena   (sel_b2_spk & ena_wide),
    .wea   ({wea_wide}),
    .addra (addr_wide[7:0]),
    .dina  (din_wide),
    .clkb  (clkb),
    .enb   (sel_b2_spk & enb_wide),
    .addrb (addr_wide[7:0]),
    .doutb (dout_b2_spk)
);

// Bank 2b: Target outputs - 16-bit, depth 512, addr [8:0]
bank_2_out u_bank2_out (
    .clka  (clka),
    .ena   (sel_b2_out & ena),
    .wea   ({wea}),
    .addra (addr[8:0]),
    .dina  (din[15:0]),
    .clkb  (clkb),
    .enb   (sel_b2_out & enb),
    .addrb (addr[8:0]),
    .doutb (dout_b2_out)
);

// Bank 3a: W_in - 16-bit, depth 2048, addr [10:0]
bank_3_win u_bank3_win (
    .clka  (clka),
    .ena   (sel_b3_win & ena),
    .wea   ({wea}),
    .addra (addr[10:0]),
    .dina  (din[15:0]),
    .clkb  (clkb),
    .enb   (sel_b3_win & enb),
    .addrb (addr[10:0]),
    .doutb (dout_b3_win)
);

// Bank 3b: W_rec - 16-bit, depth 16384, addr [13:0]
bank_3_wrec u_bank3_wrec (
    .clka  (clka),
    .ena   (sel_b3_wrec & ena),
    .wea   ({wea}),
    .addra (addr[13:0]),
    .dina  (din[15:0]),
    .clkb  (clkb),
    .enb   (sel_b3_wrec & enb),
    .addrb (addr[13:0]),
    .doutb (dout_b3_wrec)
);

// Bank 3c: W_out - 16-bit, depth 1280, addr [10:0]
bank_3_wout u_bank3_wout (
    .clka  (clka),
    .ena   (sel_b3_wout & ena),
    .wea   ({wea}),
    .addra (addr[10:0]),
    .dina  (din[15:0]),
    .clkb  (clkb),
    .enb   (sel_b3_wout & enb),
    .addrb (addr[10:0]),
    .doutb (dout_b3_wout)
);

// Bank 4a: dW_in - 32-bit, depth 2048, addr [10:0]
bank_4_dwin u_bank4_dwin (
    .clka  (clka),
    .ena   (sel_b4_dwin & ena),
    .wea   ({wea}),
    .addra (addr[10:0]),
    .dina  (din[31:0]),
    .clkb  (clkb),
    .enb   (sel_b4_dwin & enb),
    .addrb (addr[10:0]),
    .doutb (dout_b4_dwin)
);

// Bank 4b: dW_rec - 32-bit, depth 16384, addr [13:0]
bank_4_dwrec u_bank4_dwrec (
    .clka  (clka),
    .ena   (sel_b4_dwrec & ena),
    .wea   ({wea}),
    .addra (addr[13:0]),
    .dina  (din[31:0]),
    .clkb  (clkb),
    .enb   (sel_b4_dwrec & enb),
    .addrb (addr[13:0]),
    .doutb (dout_b4_dwrec)
);

// Bank 4c: dW_out - 32-bit, depth 1280, addr [10:0]
bank_4_dwout u_bank4_dwout (
    .clka  (clka),
    .ena   (sel_b4_dwout & ena),
    .wea   ({wea}),
    .addra (addr[10:0]),
    .dina  (din[31:0]),
    .clkb  (clkb),
    .enb   (sel_b4_dwout & enb),
    .addrb (addr[10:0]),
    .doutb (dout_b4_dwout)
);

// Bank 5: Neuron states - 16-bit, depth 512, addr [8:0]
bank_5_state u_bank5_state (
    .clka  (clka),
    .ena   (sel_b5 & ena),
    .wea   ({wea}),
    .addra (addr[8:0]),
    .dina  (din[15:0]),
    .clkb  (clkb),
    .enb   (sel_b5 & enb),
    .addrb (addr[8:0]),
    .doutb (dout_b5)
);

endmodule
