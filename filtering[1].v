`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.08.2025 16:37:23
// Design Name: 
// Module Name: filtering
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


module filtering #(
    parameter DECIMATION_RATIO = 64,    // Reduce data rate by 64x
    parameter OUTPUT_WIDTH = 16,        // 16-bit PCM output
    parameter CIC_WIDTH = 24           // Internal width for calculations
)(
    input  wire clk,                   // High frequency PDM clock
    input  wire reset,
    input  wire pdm_data,              // PDM input from microphone
    output reg  [OUTPUT_WIDTH-1:0] pcm_data,  // PCM output
    output reg  pcm_valid              // New PCM sample ready
);

// Step 1: Integrator stages (Low-pass filtering)
reg [CIC_WIDTH-1:0] integrator1, integrator2, integrator3;

always @(posedge clk) begin
    if (reset) begin
        integrator1 <= 0;
        integrator2 <= 0;
        integrator3 <= 0;
    end else begin
        // Convert PDM (0/1) to signed (-1/+1)
        integrator1 <= integrator1 + (pdm_data ? 1 : -1);
        integrator2 <= integrator2 + integrator1;
        integrator3 <= integrator3 + integrator2;
    end
end

// Step 2: Decimation counter
reg [5:0] decimation_counter;  // 6 bits for counter up to 64
wire decimation_tick = (decimation_counter == DECIMATION_RATIO-1);

always @(posedge clk) begin
    if (reset)
        decimation_counter <= 0;
    else
        decimation_counter <= decimation_tick ? 0 : decimation_counter + 1;
end

// Step 3: Comb stages (Differentiators) - only active at decimated rate
reg [CIC_WIDTH-1:0] comb1_delay, comb2_delay, comb3_delay;
reg [CIC_WIDTH-1:0] comb1_out, comb2_out, comb3_out;

always @(posedge clk) begin
    if (reset) begin
        comb1_delay <= 0;
        comb2_delay <= 0;
        comb3_delay <= 0;
        comb1_out <= 0;
        comb2_out <= 0;
        comb3_out <= 0;
        pcm_data <= 0;
        pcm_valid <= 0;
    end else if (decimation_tick) begin
        // Comb filters (differentiate)
        comb1_out <= integrator3 - comb1_delay;
        comb1_delay <= integrator3;
        
        comb2_out <= comb1_out - comb2_delay;
        comb2_delay <= comb1_out;
        
        comb3_out <= comb2_out - comb3_delay;
        comb3_delay <= comb2_out;
        
        // Scale and output (take upper bits)
        pcm_data <= comb3_out[CIC_WIDTH-1:CIC_WIDTH-OUTPUT_WIDTH];
        pcm_valid <= 1;
    end else begin
        pcm_valid <= 0;
    end
end

endmodule
