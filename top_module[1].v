`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.08.2025 18:14:07
// Design Name: 
// Module Name: top_module
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
module top_module (
    input  clk,
    input  reset,
    input  start,

    // PMOD MIC3 connections
    output wire JA1,   // CS
    input wire JA3,   // MISO
    output  wire JA4,   // SCLK

    output reg [7:0] led
    
);

    // Internal signals
    wire cs_reg;
    wire spi_clk;
    wire miso;
    wire [15:0] rx_reg;
    wire [11:0] raw_spi_data;
    wire spi_valid;
    wire[15:0] audio_level;
    wire [11:0] debug_raw_data;
    wire [11:0] debug_baseline;  
    wire [11:0] debug_difference;
    wire [7:0] debug_counter;
    wire debug_cal_done;
    wire [15:0] debug_scaled;
    wire volume_ready;
    
    // SPI interface instance
    interfacing mic3_interface (
        .clk(clk),
        .reset(reset),
        .start(start),
        .audio_data(raw_spi_data),
        .data_valid(spi_valid),
        .cs_reg(cs_reg),   // drive internal
        .spi_clk(spi_clk), // drive internal
        .miso(miso),       // internal
        .spi_clk_prev(),
        .bit_counter(),
        .rx_reg(rx_reg),
        .counter(),
        .state()
    );

    // Connect internals to PMOD pins
    assign JA1 = cs_reg;
    assign JA4 = spi_clk;
    assign miso = JA3;

ila_0 your_instance_name (
	.clk(clk), // input wire clk


	.probe0(reset), // input wire [0:0]  probe0  
	.probe1(raw_spi_data), // input wire [11:0]  probe1 
	.probe2(start), // input wire [0:0]  probe2 
	.probe3(cs_reg), // input wire [0:0]  probe3 
	.probe4(miso), // input wire [0:0]  probe4 
	.probe5(spi_valid), // input wire [0:0]  probe5 
	.probe6(spi_clk), // input wire [0:0]  probe6 
	.probe7(audio_level)
);

myinterfacing volume_meter (
    .clk(clk),
    .reset(reset),
    .spi_audio_data(raw_spi_data),   
    .spi_data_valid(spi_valid),      
    .audio_level(audio_level),      // THIS shows volume level!
    .level_ready(volume_ready)       
);

always @(posedge clk) begin
    if (reset) begin
        led <= 8'b00000000;
    end else begin
        if (volume_ready) begin
            if (audio_level < 300)  
                led <= 8'b00000000;      // Silent
            else if (audio_level >= 300 && audio_level < 700)  
                led <= 8'b00000001;      // Very quiet
            else if (audio_level >= 700 && audio_level < 1200)      
                led <= 8'b00000011;      // Quiet
            else if (audio_level >= 1200 && audio_level <2500)      
                led <= 8'b00000111;      // Low
            else if (audio_level >= 2500 && audio_level < 5000)   
                led <= 8'b00001111;      // Medium
            else if (audio_level >= 5000 && audio_level < 10000)   
                led <= 8'b00011111;      // Loud
            else if (audio_level >= 10000 && audio_level < 12000)  
                led <= 8'b00111111;
            else if (audio_level >= 12000 && audio_level < 15000)  
                led <= 8'b01111111;   
            else if (audio_level >= 15000)  
                led <= 8'b1111111;                
        end
    end
end

endmodule

