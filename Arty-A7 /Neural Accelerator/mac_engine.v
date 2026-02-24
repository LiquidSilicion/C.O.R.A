module mac_engine(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    // BRAM interface
    output reg  [3:0]  addr_w_in,
    input  wire signed [15:0] w_in_data,

    // 16 inputs packed into 256-bit bus
    input  wire signed [255:0] input_vec,

    output reg  signed [31:0] mac_out,
    output reg         done
);

//////////////////////////////////////////////////////////////
// Internal Registers
//////////////////////////////////////////////////////////////

reg [4:0] cycle_count;          // 0 → 18
reg signed [31:0] accumulator;

reg [3:0] index_d1;
reg [3:0] index_d2;

reg start_d;
wire start_pulse;

assign start_pulse = start & ~start_d;

// Extract 16-bit slice
wire signed [15:0] current_input;
assign current_input = input_vec[index_d2*16 +: 16];

//////////////////////////////////////////////////////////////
// Start pulse detection
//////////////////////////////////////////////////////////////

always @(posedge clk)
begin
    start_d <= start;
end

//////////////////////////////////////////////////////////////
// Main MAC Logic
//////////////////////////////////////////////////////////////

always @(posedge clk)
begin
    if (rst) begin
        cycle_count <= 0;
        addr_w_in   <= 0;
        accumulator <= 0;
        mac_out     <= 0;
        done        <= 0;
        index_d1    <= 0;
        index_d2    <= 0;
    end
    else begin

        ///////////////////////////////////////////////////////
        // On new start pulse → reset computation
        ///////////////////////////////////////////////////////
        if (start_pulse) begin
            cycle_count <= 0;
            accumulator <= 0;
            done        <= 0;
        end

        ///////////////////////////////////////////////////////
        // Run computation while not finished
        ///////////////////////////////////////////////////////
        if (!done) begin

            // Generate addresses only first 16 cycles
            if (cycle_count < 16)
                addr_w_in <= cycle_count[3:0];
            else
                addr_w_in <= 0;

            // Pipeline index for 2-cycle BRAM latency
            index_d1 <= cycle_count[3:0];
            index_d2 <= index_d1;

            // Accumulate only when BRAM data is valid
            // Valid window: cycles 2 → 17
            if (cycle_count >= 2 && cycle_count < 18) begin
                accumulator <= accumulator +
                               (w_in_data * current_input);
            end

            cycle_count <= cycle_count + 1;

            // Finish exactly after pipeline drains
            if (cycle_count == 18) begin
                mac_out <= accumulator;
                done    <= 1;
            end

        end
    end
end

endmodule
