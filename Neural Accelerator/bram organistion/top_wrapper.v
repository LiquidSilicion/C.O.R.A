module top_wrapper (
    input wire clk_in
);

wire        clka, clkb;
reg         ena  = 0;
reg         enb  = 0;
reg         wea  = 0;
reg  [16:0] addr = 0;
reg  [31:0] din  = 0;
wire [31:0] dout;
reg         ena_wide  = 0;
reg         enb_wide  = 0;
reg         wea_wide  = 0;
reg  [8:0]  addr_wide = 0;
reg  [127:0] din_wide = 0;
wire [127:0] dout_wide;

// clka and clkb are wires now - assign is valid
assign clka = clk_in;
assign clkb = clk_in;

snn_bram_top u_snn_bram (
    .clka     (clka),
    .clkb     (clkb),
    .ena      (ena),
    .enb      (enb),
    .wea      (wea),
    .addr     (addr),
    .din      (din),
    .dout     (dout),
    .ena_wide (ena_wide),
    .enb_wide (enb_wide),
    .wea_wide (wea_wide),
    .addr_wide(addr_wide),
    .din_wide (din_wide),
    .dout_wide(dout_wide)
);

endmodule
