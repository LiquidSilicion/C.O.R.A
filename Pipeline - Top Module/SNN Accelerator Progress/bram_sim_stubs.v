// =============================================================================
// bram_sim_stubs.v — BEHAVIORAL SIMULATION STUBS FOR ALL INFERENCE BRAMs
// =============================================================================
// Covers all five IPs created by create_brams.tcl:
//   bank_1_vm    16-bit × 1024   (LIF membrane potential V_m)
//   bank_1_s    128-bit × 512    (Spike history s[t])
//   bank_3_win   16-bit × 2048   (W_in weights)
//   bank_3_wrec  16-bit × 16384  (W_rec weights)
//   bank_3_wout  16-bit × 2048   (W_out weights)
//
// All are Simple Dual Port RAM:
//   Port A : write (clka/ena/wea/addra/dina/douta)
//   Port B : read  (clkb/enb/addrb/doutb)
//   Latency: 1 clock cycle, no output register
//   Enable pins are EXPOSED (Use_ENA_Pin / Use_ENB_Pin)
//
// HOW TO USE:
//   Add this file to Vivado simulation sources only.
//   Do NOT add to synthesis.  The real IPs take over in synthesis/impl.
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// bank_1_vm : 16-bit × 1024   (LIF V_m, 128 neurons, zero-padded to 1024)
// =============================================================================
module bank_1_vm (
    input  wire        clka,
    input  wire        ena,
    input  wire        wea,
    input  wire [9:0]  addra,
    input  wire [15:0] dina,
    output reg  [15:0] douta,

    input  wire        clkb,
    input  wire        enb,
    input  wire [9:0]  addrb,
    output reg  [15:0] doutb
);
    reg [15:0] mem [0:1023];
    integer i;
    initial for (i = 0; i < 1024; i = i + 1) mem[i] = 16'h0000;

    always @(posedge clka) begin
        if (ena) begin
            if (wea) mem[addra] <= dina;
            douta <= mem[addra];
        end
    end

    always @(posedge clkb) begin
        if (enb) doutb <= mem[addrb];
    end
endmodule


// =============================================================================
// bank_1_s : 128-bit × 512   (Spike history)
// =============================================================================
module bank_1_s (
    input  wire          clka,
    input  wire          ena,
    input  wire          wea,
    input  wire [8:0]    addra,
    input  wire [127:0]  dina,
    output reg  [127:0]  douta,

    input  wire          clkb,
    input  wire          enb,
    input  wire [8:0]    addrb,
    output reg  [127:0]  doutb
);
    reg [127:0] mem [0:511];
    integer i;
    initial for (i = 0; i < 512; i = i + 1) mem[i] = 128'h0;

    always @(posedge clka) begin
        if (ena) begin
            if (wea) mem[addra] <= dina;
            douta <= mem[addra];
        end
    end

    always @(posedge clkb) begin
        if (enb) doutb <= mem[addrb];
    end
endmodule


// =============================================================================
// bank_3_win : 16-bit × 2048   (W_in weights, NI=16 × NH=128)
// =============================================================================
module bank_3_win (
    input  wire        clka,
    input  wire        ena,
    input  wire        wea,
    input  wire [10:0] addra,
    input  wire [15:0] dina,
    output reg  [15:0] douta,

    input  wire        clkb,
    input  wire        enb,
    input  wire [10:0] addrb,
    output reg  [15:0] doutb
);
    reg [15:0] mem [0:2047];
    integer i;
    initial for (i = 0; i < 2048; i = i + 1) mem[i] = 16'h0000;

    always @(posedge clka) begin
        if (ena) begin
            if (wea) mem[addra] <= dina;
            douta <= mem[addra];
        end
    end

    always @(posedge clkb) begin
        if (enb) doutb <= mem[addrb];
    end
endmodule


// =============================================================================
// bank_3_wrec : 16-bit × 16384   (W_rec weights, NH=128 × NH=128)
// =============================================================================
module bank_3_wrec (
    input  wire        clka,
    input  wire        ena,
    input  wire        wea,
    input  wire [13:0] addra,
    input  wire [15:0] dina,
    output reg  [15:0] douta,

    input  wire        clkb,
    input  wire        enb,
    input  wire [13:0] addrb,
    output reg  [15:0] doutb
);
    reg [15:0] mem [0:16383];
    integer i;
    initial for (i = 0; i < 16384; i = i + 1) mem[i] = 16'h0000;

    always @(posedge clka) begin
        if (ena) begin
            if (wea) mem[addra] <= dina;
            douta <= mem[addra];
        end
    end

    always @(posedge clkb) begin
        if (enb) doutb <= mem[addrb];
    end
endmodule


// =============================================================================
// bank_3_wout : 16-bit × 2048   (W_out weights, NH=128 × NO=10 = 1280 used)
// =============================================================================
module bank_3_wout (
    input  wire        clka,
    input  wire        ena,
    input  wire        wea,
    input  wire [10:0] addra,
    input  wire [15:0] dina,
    output reg  [15:0] douta,

    input  wire        clkb,
    input  wire        enb,
    input  wire [10:0] addrb,
    output reg  [15:0] doutb
);
    reg [15:0] mem [0:2047];
    integer i;
    initial for (i = 0; i < 2048; i = i + 1) mem[i] = 16'h0000;

    always @(posedge clka) begin
        if (ena) begin
            if (wea) mem[addra] <= dina;
            douta <= mem[addra];
        end
    end

    always @(posedge clkb) begin
        if (enb) doutb <= mem[addrb];
    end
endmodule
