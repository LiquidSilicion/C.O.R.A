module lif_neuron #(
    parameter LEAK_FACTOR = 15'd31130,  // 0.95 * 32768
    parameter THRESHOLD   = 32'd16000,
    parameter REFRAC      = 4'd8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_en,    // 16kHz pulse
    input  wire [15:0] ihc_in,       // 16-bit unsigned IHC envelope
    output reg         spike         // 1 = fired, 0 = silent
);

    // ----------------------------------------------------------
    //  Membrane potential - 32-bit unsigned
    //  Needs 32-bit because resonance amplifies state:
    //  V_max = ihc_max / (1 - leak) = 10000 / 0.05 = 200,000
    //  16-bit max = 32,767 ? overflow
    //  32-bit max = 4,294,967,295 ? fits comfortably
    // ----------------------------------------------------------
    reg [31:0] membrane;
    reg  [3:0] refrac_cnt;

    // ----------------------------------------------------------
    //  STEP 1 - Leak
    //  V_leaked = V * LEAK_FACTOR / 32768
    //  Q0.15 multiply: result >> 15
    //  48-bit intermediate prevents overflow
    // ----------------------------------------------------------
    wire [47:0] leak_full   = membrane * LEAK_FACTOR;
    wire [31:0] mem_leaked  = leak_full[46:15];  // >> 15

    // ----------------------------------------------------------
    //  STEP 2 - Integrate
    //  Add IHC input to leaked membrane
    //  33-bit to catch overflow
    // ----------------------------------------------------------
    wire [32:0] mem_next = {1'b0, mem_leaked} + {1'b0, 16'b0, ihc_in};

    // ----------------------------------------------------------
    //  STEP 3 - Fire / Integrate / Refractory
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            membrane   <= 32'd0;
            refrac_cnt <= 4'd0;
            spike      <= 1'b0;

        end else if (sample_en) begin
            spike <= 1'b0;  // default no spike

            if (refrac_cnt > 0) begin
                // ----------------------------------------
                //  REFRACTORY - forced silent
                //  Still integrates (biological accuracy)
                //  Counts down to 0 then allows firing
                // ----------------------------------------
                refrac_cnt <= refrac_cnt - 1;
                membrane   <= mem_next[31:0];

            end else if (mem_next[31:0] >= THRESHOLD) begin
                // ----------------------------------------
                //  FIRE - threshold crossed
                // ----------------------------------------
                spike      <= 1'b1;
                membrane   <= 32'd0;
                refrac_cnt <= REFRAC;

            end else begin
                // ----------------------------------------
                //  SUB-THRESHOLD - keep integrating
                // ----------------------------------------
                membrane   <= mem_next[31:0];
            end
        end
    end

endmodule
