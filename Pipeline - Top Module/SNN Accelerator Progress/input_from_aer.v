// input_from_aer.v - Fixed: All outputs always driven

module input_from_aer (
    input wire clk,
    input wire rst_n,
    input wire [23:0] in,
    input wire aer_valid,
    
    output reg spike_detected,
    output reg [3:0] channel_Id,
    output reg [19:0] timestamp,
    output reg timestamp_valid
);

    // 3-stage pipeline registers
    reg [23:0] pipe_stage0;
    reg [23:0] pipe_stage1;
    reg [23:0] pipe_stage2;
    reg        valid_stage0;
    reg        valid_stage1;
    reg        valid_stage2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset ALL registers
            pipe_stage0    <= 24'b0;
            pipe_stage1    <= 24'b0;
            pipe_stage2    <= 24'b0;
            valid_stage0   <= 1'b0;
            valid_stage1   <= 1'b0;
            valid_stage2   <= 1'b0;
            channel_Id     <= 4'b0;
            timestamp      <= 20'b0;
            spike_detected <= 1'b0;
            timestamp_valid<= 1'b0;  // ✅ Explicitly reset to 0
        end else begin
            // Stage 1: Capture input
            if (aer_valid) begin
                pipe_stage0  <= in;
                valid_stage0 <= 1'b1;
            end else begin
                valid_stage0 <= 1'b0;
            end

            // Stage 2: Propagate
            pipe_stage1  <= pipe_stage0;
            valid_stage1 <= valid_stage0;

            // Stage 3: Output + decode
            pipe_stage2  <= pipe_stage1;
            valid_stage2 <= valid_stage1;

            // ✅ ALWAYS drive outputs (no if/else missing branches)
            if (valid_stage2) begin
                channel_Id     <= pipe_stage2[23:20];
                timestamp      <= pipe_stage2[19:0];
                timestamp_valid<= 1'b1;
                spike_detected <= 1'b1;
            end else begin
                channel_Id     <= channel_Id;     // Hold value
                timestamp      <= timestamp;      // Hold value
                timestamp_valid<= 1'b0;           // ✅ Explicitly drive 0
                spike_detected <= 1'b0;           // ✅ Explicitly drive 0
            end
        end
    end

endmodule
