`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.04.2026 15:12:30
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
module cora_top (
    input  wire        clk_100MHz,
    input  wire        rst_n,
    input  wire        window_done,
    input  wire [3:0]  cmd_id,
    input  wire [16:0] final_score,
    output wire        uart_tx,
    output wire        tx_busy
);
    uart_result_hex_tx #(
        .CLK_FREQ (100_000_000),
        .BAUD_RATE(115200)
    ) u_uart (
        .clk       (clk_100MHz),
        .rst_n     (rst_n),
        .tx_trigger(window_done),
        .cmd_id    (cmd_id),
        .score_in  (final_score),
        .uart_tx   (uart_tx),
        .tx_busy   (tx_busy)
    );
endmodule