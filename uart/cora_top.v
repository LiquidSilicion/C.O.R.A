`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.04.2026 23:56:51
// Design Name: 
// Module Name: cora_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module cora_top (
    input  wire        clk_100MHz,
    input  wire        rst_n,
    input  wire        window_done,      // From FSM 4 (S15)
    input  wire [3:0]  cmd_id,           // From S14 Overlap Voter
    input  wire [16:0] final_score,      // From S13 Output Layer
    output wire        uart_tx,          // To PMOD0 Pin 1
    output wire        tx_busy
);

    uart_result_hex_tx #(
        .CLK_FREQ (100_000_000),
        .BAUD_RATE(115200)
    ) u_result_uart (
        .clk        (clk_100MHz),
        .rst_n      (rst_n),
        .tx_trigger (window_done),      // CORA v4: FSM 2 rule
        .cmd_id     (cmd_id),
        .score_in   (final_score),
        .uart_tx    (uart_tx),
        .tx_busy    (tx_busy)
    );

endmodule
