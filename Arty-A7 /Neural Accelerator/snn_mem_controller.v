module snn_mem_controller(
    input  wire        clk,
    input  wire        we,
    input  wire [15:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);

//////////////////////////////////////////////////////////////
// Bank Select
/////////////////// ///////////////////////////////////////////

wire [3:0] bank_sel = addr[15:12];

//////////////////////////////////////////////////////////////
// Local Word Address (32-bit aligned)
//////////////////////////////////////////////////////////////

wire [13:0] word_addr = addr[15:2];   // drop bottom 2 bits

//////////////////////////////////////////////////////////////
// Read Data Wires
//////////////////////////////////////////////////////////////

wire [31:0] bank0_rdata;
wire [31:0] bank1_rdata;
wire [31:0] bank2_rdata;
wire [31:0] bank3_rdata;
wire [31:0] bank4_rdata;
wire [31:0] bank5_rdata;

//////////////////////////////////////////////////////////////
// BANK 0 - CONFIG (0x0000-0x0FFF)
//////////////////////////////////////////////////////////////

bram_bank0_config u_bank0 (
    .clka(clk),
    .ena(1'b1),
    .wea((bank_sel == 4'h0) ? we : 1'b0),
    .addra(word_addr[9:0]),      // 1024 depth
    .dina(wdata),
    .douta(bank0_rdata)
);

//////////////////////////////////////////////////////////////
// BANK 1 - FORWARD (0x1000-0x2FFF)
//////////////////////////////////////////////////////////////

bram_bank1_forward u_bank1 (
    .clka(clk),
    .ena((bank_sel == 4'h1) || (bank_sel == 4'h2)),
    .wea(((bank_sel == 4'h1)||(bank_sel == 4'h2)) ? we : 1'b0),
    .addra(word_addr[10:0]),     // 2048 depth
    .dina(wdata),
    .douta(bank1_rdata)
);

//////////////////////////////////////////////////////////////
// BANK 2 - TARGET (0x3000-0x3FFF)
//////////////////////////////////////////////////////////////

bram_bank2_target u_bank2 (
    .clka(clk),
    .ena(bank_sel == 4'h3),
    .wea((bank_sel == 4'h3) ? we : 1'b0),
    .addra(word_addr[9:0]),
    .dina(wdata),
    .douta(bank2_rdata)
);

//////////////////////////////////////////////////////////////
// BANK 3 - WEIGHTS (0x4000-0x7FFF)
//////////////////////////////////////////////////////////////

bram_bank3_weights u_bank3 (
    .clka(clk),
    .ena(bank_sel >= 4'h4 && bank_sel <= 4'h7),
    .wea((bank_sel >= 4'h4 && bank_sel <= 4'h7) ? we : 1'b0),
    .addra(word_addr[11:0]),     // 4096 depth
    .dina(wdata),
    .douta(bank3_rdata)
);

//////////////////////////////////////////////////////////////
// BANK 4 - GRADIENTS (0x9000-0xCFFF)
//////////////////////////////////////////////////////////////

bram_bank4_grad u_bank4 (
    .clka(clk),
    .ena(bank_sel >= 4'h9 && bank_sel <= 4'hC),
    .wea((bank_sel >= 4'h9 && bank_sel <= 4'hC) ? we : 1'b0),
    .addra(word_addr[11:0]),
    .dina(wdata),
    .douta(bank4_rdata)
);

//////////////////////////////////////////////////////////////
// BANK 5 - NEURON STATES (0xE000-0xE3FF)
//////////////////////////////////////////////////////////////

bram_bank5_state u_bank5 (
    .clka(clk),
    .ena(bank_sel == 4'hE),
    .wea((bank_sel == 4'hE) ? we : 1'b0),
    .addra(word_addr[7:0]),      // 256 depth
    .dina(wdata),
    .douta(bank5_rdata)
);

//////////////////////////////////////////////////////////////
// Read Mux
//////////////////////////////////////////////////////////////

always @(*) begin
    case(bank_sel)
        4'h0: rdata = bank0_rdata;
        4'h1,
        4'h2: rdata = bank1_rdata;
        4'h3: rdata = bank2_rdata;
        4'h4,4'h5,4'h6,4'h7: rdata = bank3_rdata;
        4'h9,4'hA,4'hB,4'hC: rdata = bank4_rdata;
        4'hE: rdata = bank5_rdata;
        default: rdata = 32'h00000000;
    endcase
end

endmodule
