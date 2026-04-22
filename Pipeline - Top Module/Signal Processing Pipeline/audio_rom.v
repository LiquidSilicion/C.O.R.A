
module audio_rom #(
    parameter N_SAMPLES = 20160   // 20160 samples = 1.26s @ 16kHz
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_en,   // 1-cycle pulse @ 16kHz (every 6250 cycles @ 100MHz)
    output reg  [15:0] x_out,       // 16-bit signed PCM to VAD
    output reg         done         // pulses high when playback completes
);
    // ROM storage: 20160 × 16-bit samples
    reg [15:0] rom [0:N_SAMPLES-1];
    initial $readmemh("coefficients.mem", rom);
    
    // FIXED: 15-bit address supports up to 32,768 samples
    reg [14:0] addr;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            addr  <= 15'd0;
            x_out <= 16'h0;
            done  <= 1'b0;
        end else if (sample_en) begin
            if (addr < N_SAMPLES - 1) begin
                // Output current sample, then increment
                x_out <= rom[addr];
                addr  <= addr + 15'd1;
                done  <= 1'b0;
            end else begin
                // FIXED: Output the FINAL sample before asserting done
                x_out <= rom[addr];   // rom[20159]
                done  <= 1'b1;        // Signal completion
                // Hold addr at end (optional: wrap or stall)
            end
        end
    end
    
endmodule
