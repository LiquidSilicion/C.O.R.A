`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/30/2026 02:38:24 AM
// Design Name: 
// Module Name: nonlinear
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


module nonlinear_compression(
    input  wire        clk,
    input  wire        rst,
    input  wire        valid_in,
    input  wire [15:0] x_in,
    output reg  [15:0] y_out,
    output reg         valid_out
);

    // 1. Block RAM declaration (forces Vivado to use BRAM, not LUTs)
    (* ram_style = "block" *) reg [15:0] lut_mem [0:1023];

    // 2. Load binary file at simulation & synthesis time
    initial begin
        $readmemh("ni_lut.mem", lut_mem);
    end

    // 3. Absolute value (unchanged)
    wire [14:0] abs_x_raw;
    wire [14:0] abs_x;
    assign abs_x_raw = x_in[15] ? (~x_in[14:0] + 1'b1) : x_in[14:0];
    assign abs_x     = (x_in == 16'sh8000) ? 15'h7FFF : abs_x_raw;

    // 4. LUT index (unchanged)
    wire [9:0] lut_index;
    assign lut_index = abs_x[14:5];

    // 5. Registered output with valid gating (unchanged timing)
    always @(posedge clk) begin
        if (rst) begin
            y_out     <= 16'd0;
            valid_out <= 1'b0;
        end
        else if (valid_in) begin
            y_out     <= lut_mem[lut_index];  // ← Reads from BRAM instead of function
            valid_out <= 1'b1;
        end
        else begin
            valid_out <= 1'b0;
        end
    end

endmodule
