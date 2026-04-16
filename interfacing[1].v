`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.08.2025 11:46:40
// Design Name: 
// Module Name: interfacing
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


module interfacing(
input clk,
input reset,
input start,
output reg [11:0]audio_data,

output reg data_valid,
output reg cs_reg,

output reg spi_clk,
input wire miso,
output reg spi_clk_prev,
output reg [4:0] bit_counter,
output reg [15:0] rx_reg,


    
output reg [7:0]counter,
output reg state

    );

    // Using parameters for states
parameter IDLE = 1'b0,
          TRANSFER = 1'b1;
          
parameter CLK_DIV = 6;      // Clock divider (100MHz/25=4MHz SPI clock)
parameter IDLE_CLK = 1'b0;           
          
    
    always@(posedge clk or posedge reset)begin
    if (reset) begin
        counter <= 0;
        spi_clk <= IDLE_CLK;
    end else begin
        spi_clk_prev <= spi_clk;
        
        if (cs_reg) begin
            counter <= 0;
            spi_clk <= IDLE_CLK;
        end else begin
            if (counter == CLK_DIV-1) begin
                counter <= 0;
                spi_clk <= ~spi_clk;
            end else begin
                counter <= counter + 1;
            end
        end
    end
end

wire spi_clk_fall = ( spi_clk_prev & ~spi_clk); // detect falling edge

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state       <= IDLE;
        cs_reg      <= 1'b1;
        rx_reg      <= 0;
        bit_counter <= 0;
        audio_data  <= 0;
        data_valid  <= 1'b0;
    end 
    else begin
        case (state)

            IDLE: begin
                cs_reg     <= 1'b1;     
                data_valid <= 1'b0;   

                if (start) begin
                    cs_reg      <= 1'b0;   
                    bit_counter <= 16;  
                    rx_reg      <= 0;
                    state       <= TRANSFER;
                end
            end

            // --------------------
            TRANSFER: begin
                if (spi_clk_prev == 1'b0 && spi_clk == 1'b1) begin
                    rx_reg      <= {rx_reg[14:0], miso};
                    bit_counter <= bit_counter - 1;
                    if (bit_counter == 1) begin
                        audio_data <= {rx_reg[10:0], miso};
                        data_valid <= 1'b1;   
                        cs_reg     <= 1'b1;
                        state      <= IDLE;
                    end
                end
            end

        endcase
    end
end


endmodule
