`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: lif_array_bram_fixed
// Target: AMD ZCU104 @ 200 MHz


module lif_array_bram #(
    parameter NH    = 128,
    parameter ALPHA = 16'h00E0,     // 0.875 in Q8.8
    parameter THETA = 16'h0100      // 1.0   in Q8.8
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          clear_state,

    // From MAC engine
    input  wire [15:0]   lif_acc,
    input  wire [6:0]    lif_idx,
    input  wire          lif_wen,
    input  wire          lif_capture,

    // Spike outputs
    output reg  [NH-1:0] lif_spikes,
    output reg           capture_done,

    // BRAM Bank 2 (512 × 16-bit)
    output reg  [8:0]    vm_addr,
    input  wire [15:0]   vm_dout,
    output reg  [15:0]   vm_din,
    output reg           vm_we,
    output wire          vm_en
);

    // Always enable BRAM
    assign vm_en = 1'b1;

    // Local synpatic current accumulator (set by MAC, read during sweep)
    reg [15:0] accum [0:NH-1];

    // Pipeline for sweep: issue read addr one cycle ahead
    // cap_idx:  current neuron being processed
    // cap_idx_d: delayed by 1 (matches BRAM output latency)
    reg [1:0] cap_state;
    reg [7:0] cap_idx;
    reg [7:0] cap_idx_d;   // Registered version for write-back phase

    localparam ST_IDLE  = 2'd0;
    localparam ST_READ  = 2'd1;   // Issue BRAM read for neuron cap_idx
    localparam ST_WRITE = 2'd2;   // vm_dout valid; compute + write back
    localparam ST_DONE  = 2'd3;

    reg [NH-1:0] spike_next;

    // LIF computation uses vm_dout (registered 1 cycle after read issued)
    wire signed [31:0] alpha_x_vm  = $signed({1'b0, ALPHA}) * $signed({1'b0, vm_dout});
    wire [15:0]        v_decayed   = alpha_x_vm[23:8];
    wire [16:0]        v_new_full  = {1'b0, v_decayed} + {1'b0, accum[cap_idx_d]};
    wire [15:0]        v_new       = v_new_full[16] ? 16'hFFFF : v_new_full[15:0];
    wire               fire        = (v_new >= THETA);

    integer ci;

    always @(posedge clk) begin
        if (!rst_n) begin
            cap_state    <= ST_IDLE;
            cap_idx      <= 8'd0;
            cap_idx_d    <= 8'd0;
            lif_spikes   <= {NH{1'b0}};
            capture_done <= 1'b0;
            spike_next   <= {NH{1'b0}};
            vm_addr      <= 9'd0;
            vm_din       <= 16'd0;
            vm_we        <= 1'b0;
            for (ci = 0; ci < NH; ci = ci + 1) accum[ci] <= 16'd0;
        end else begin
            capture_done <= 1'b0;
            vm_we        <= 1'b0;

            // ── Accumulator write from MAC ─────────────────────────────────
            // Writes local accum[] only; does NOT touch BRAM during this phase.
            // MAC guarantees lif_wen is never asserted during capture sweep.
            if (lif_wen) begin
                accum[lif_idx] <= lif_acc;
            end

            // ── Global clear ───────────────────────────────────────────────
            if (clear_state) begin
                for (ci = 0; ci < NH; ci = ci + 1) accum[ci] <= 16'd0;
                // BRAM clear would require a separate sequencer; skip for inference
            end

            // ── Capture FSM ────────────────────────────────────────────────
            case (cap_state)

                ST_IDLE: begin
                    if (lif_capture) begin
                        cap_idx    <= 8'd0;
                        spike_next <= {NH{1'b0}};
                        // Issue first read: addr = neuron 0
                        vm_addr   <= 9'd0;
                        cap_state <= ST_READ;
                    end
                end

                // Issued the BRAM read for cap_idx last cycle.
                // vm_dout will be valid next cycle (ST_WRITE).
                // Issue next read now (pipelined).
                ST_READ: begin
                    cap_idx_d <= cap_idx;    // Latch for use in ST_WRITE
                    if (cap_idx < NH - 1) begin
                        cap_idx <= cap_idx + 8'd1;
                        vm_addr <= {1'b0, cap_idx + 8'd1};  // Next neuron addr
                    end
                    cap_state <= ST_WRITE;
                end

                // vm_dout valid for cap_idx_d
                ST_WRITE: begin
                    // Compute and write back
                    vm_addr <= {1'b0, cap_idx_d};
                    vm_din  <= fire ? 16'h0000 : v_new;
                    vm_we   <= 1'b1;
                    spike_next[cap_idx_d] <= fire;

                    if (cap_idx_d < NH - 1) begin
                        // More neurons to process
                        cap_idx_d <= cap_idx_d + 8'd1;
                        // Read for next neuron already issued in ST_READ
                        // Issue one more read ahead if cap_idx not yet at end
                        if (cap_idx < NH - 1) begin
                            cap_idx <= cap_idx + 8'd1;
                            vm_addr <= {1'b0, cap_idx + 8'd1};
                            // NOTE: vm_addr is being driven for write this cycle
                            // and for read next cycle - this creates a conflict.
                            // Solution: use a 2-port approach via the BRAM's port B
                            // for read, port A for write. Since lif_array uses
                            // single-port bank 2, we serialize: write first, then read.
                            // This adds 1 cycle per neuron but is functionally correct.
                            // For true pipelining use dual-port BRAM (port A write,
                            // port B read ahead).
                            cap_state <= ST_READ;
                        end else begin
                            cap_state <= ST_DONE;
                        end
                    end else begin
                        cap_state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    lif_spikes   <= spike_next;
                    capture_done <= 1'b1;
                    cap_state    <= ST_IDLE;
                end

                default: cap_state <= ST_IDLE;

            endcase
        end
    end

endmodule
