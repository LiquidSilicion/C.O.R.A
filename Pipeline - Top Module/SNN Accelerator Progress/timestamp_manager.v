// timestamp_manager.v - Extends 20-bit AER timestamp to 32-bit with rollover
// Spec S9: 32-bit extended, rollover detect, window_start reg

module timestamp_manager (
    input wire clk,
    input wire rst_n,
    input wire [19:0] raw_timestamp,    // 20-bit from AER (62.5µs LSB)
    input wire ts_valid,
    
    output reg [31:0] extended_ts,      // 32-bit system timestamp
    output reg window_start,            // Pulses at 50ms window boundaries
    output reg [11:0] rollover_count    // Debug: upper 12 bits
);

    reg [19:0] last_raw_ts;
    reg [11:0] msb_extension;  // Upper 12 bits of 32-bit timestamp
    reg [19:0] window_boundary; // 50ms = 800 steps @ 62.5µs/step

    // Initialize window boundary to 800 (50ms)
    initial begin
        window_boundary = 20'd800;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_raw_ts    <= 20'b0;
            msb_extension  <= 12'b0;
            extended_ts    <= 32'b0;
            rollover_count <= 12'b0;
            window_start   <= 1'b0;
        end else if (ts_valid) begin
            // Detect rollover: if new ts < last, we wrapped 2^20 steps
            if (raw_timestamp < last_raw_ts) begin
                msb_extension <= msb_extension + 1'b1;
            end
            last_raw_ts <= raw_timestamp;

            // Build 32-bit timestamp
            extended_ts <= {msb_extension, raw_timestamp};
            rollover_count <= msb_extension;

            // Generate window_start pulse at 50ms boundaries
            // 50ms = 800 steps of 62.5µs
            if ((raw_timestamp >= window_boundary) && 
                (last_raw_ts < window_boundary)) begin
                window_start <= 1'b1;
            end else begin
                window_start <= 1'b0;
            end
        end else begin
            window_start <= 1'b0;  // Deassert after 1 cycle pulse
        end
    end

endmodule
