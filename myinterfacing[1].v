`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 31.08.2025 11:30:35
// Design Name: 
// Module Name: myinterfacing
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


module myinterfacing(
    input clk,
    input reset,
    input [11:0] spi_audio_data,
    input spi_data_valid,
    output reg [15:0] audio_level,
    output reg level_ready,
    // Debug outputs
    output reg [11:0] debug_raw_data,
    output reg [11:0] debug_baseline,
    output reg [11:0] debug_difference,
    output reg [7:0] debug_counter,
    output reg debug_cal_done,
    output reg [15:0] debug_scaled,// Simple baseline calculation
    output reg [17:0] baseline_sum,
    output reg [7:0] sample_count,
    
      output reg [11:0] baseline,
      output reg calibration_done,
      output reg [11:0] audio_diff
);



    always @(posedge clk) begin
        if (reset) begin
            // Reset everything
            audio_level <= 0;
            level_ready <= 0;
            baseline_sum <= 0;
            sample_count <= 0;
            baseline <= 12'd2048;  // Default middle value
            calibration_done <= 0;
            audio_diff <= 0;
            
            // Reset debug outputs
            debug_raw_data <= 0;
            debug_baseline <= 0;
            debug_difference <= 0;
            debug_counter <= 0;
            debug_cal_done <= 0;
            debug_scaled <= 0;
            
        end else if (spi_data_valid) begin
            
            // ALWAYS update debug raw data
            debug_raw_data <= spi_audio_data;
            debug_counter <= sample_count;
            debug_cal_done <= calibration_done;
            
            // Step 1: Calibration (first 64 samples)
            if (!calibration_done) begin
                if (sample_count < 64) begin
                    baseline_sum <= baseline_sum + spi_audio_data;
                    sample_count <= sample_count + 1;
                    debug_baseline <= baseline_sum[17:6];  // Show running average
                    
                    // During calibration: OUTPUT ZERO & NOT READY
                    audio_level <= 0;
                    level_ready <= 0;
                end else begin
                    baseline <= baseline_sum[17:6];  // Divide by 64 (shift by 6)
                    calibration_done <= 1;
                    debug_baseline <= baseline_sum[17:6];
                    
                    // When calibration done: STILL OUTPUT ZERO
                    audio_level <= 0;
                    level_ready <= 0;
                end
                
            end else begin
                // Step 2: Calculate difference from baseline
                if (spi_audio_data > baseline) begin
                    audio_diff = spi_audio_data - baseline;
                end else begin
                    audio_diff = baseline - spi_audio_data;
                end
                
                debug_baseline <= baseline;
                debug_difference <= audio_diff;
                
                // Step 3: Simple scaling - just multiply by 8
                debug_scaled <= {audio_diff, 3'b000};  // Multiply by 8
                
                // Step 4: Output final level (REAL VOLUME!)
                audio_level <= {audio_diff, 3'b000};  // This is now REAL volume data
                level_ready <= 1; // Signal that REAL data is ready
            end
        end else begin
            level_ready <= 0;
        end
    end

endmodule
