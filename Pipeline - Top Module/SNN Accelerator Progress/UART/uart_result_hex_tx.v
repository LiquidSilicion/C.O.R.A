`timescale 1ns / 1ps
module uart_result_hex_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                tx_trigger,
    input  wire [3:0]          cmd_id,
    input  wire signed [16:0]  score_in,
    output wire                uart_tx,
    output wire                tx_busy
);

    // ── Score converter ──────────────────────────────────────
    wire [6:0] percent_val;
    score_percent #(.SCORE_WIDTH(17),.PERCENT_BITS(7)) u_sc (
        .score_in(score_in), .percent_out(percent_val)
    );

    // ── Baud generator ───────────────────────────────────────
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;  // 868
    reg [9:0] baud_cnt;
    reg       baud_tick;

    always @(posedge clk) begin
        if (!rst_n) begin
            baud_cnt  <= 0;
            baud_tick <= 0;
        end else begin
            baud_tick <= 0;
            if (baud_cnt == BAUD_DIV - 1) begin
                baud_cnt  <= 0;
                baud_tick <= 1;   // one-cycle pulse at end of baud period
            end else begin
                baud_cnt <= baud_cnt + 1;
            end
        end
    end

    // ── UART TX PHY ──────────────────────────────────────────
    // States: 0=IDLE, 1=START, 2=DATA, 3=STOP
    reg [1:0]  phy_state;
    reg [7:0]  shift_reg;
    reg [3:0]  bit_cnt;
    reg        tx_reg;
    reg        phy_done;   // one-cycle pulse when byte sent
    reg        phy_load;   // one-cycle load request from sequencer
    reg [7:0]  phy_data;   // byte to send

    assign uart_tx = tx_reg;
    assign tx_busy = (phy_state != 0);

    always @(posedge clk) begin
        if (!rst_n) begin
            phy_state <= 0;
            tx_reg    <= 1'b1;
            bit_cnt   <= 0;
            phy_done  <= 0;
        end else begin
            phy_done <= 0;
            case (phy_state)
                0: begin  // IDLE
                    tx_reg <= 1'b1;
                    if (phy_load) begin
                        shift_reg <= phy_data;
                        phy_state <= 1;
                    end
                end
                1: begin  // START BIT - wait one full baud
                    tx_reg <= 1'b0;
                    if (baud_tick) begin
                        bit_cnt   <= 0;
                        phy_state <= 2;
                    end
                end
                2: begin  // DATA BITS
                    tx_reg <= shift_reg[0];
                    if (baud_tick) begin
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        bit_cnt   <= bit_cnt + 1;
                        if (bit_cnt == 7)
                            phy_state <= 3;
                    end
                end
                3: begin  // STOP BIT
                    tx_reg <= 1'b1;
                    if (baud_tick) begin
                        phy_state <= 0;
                        phy_done  <= 1;
                    end
                end
            endcase
        end
    end

    // ── Data latch + sequencer ───────────────────────────────
    // seq_state: 0=IDLE,1=sending CMD,2=sending C_HI,
    //            3=sending C_LO,4=sending LF,5=DONE
    reg [2:0]  seq_state;
    reg [3:0]  cmd_reg;
    reg [6:0]  pct_reg;

    function [7:0] to_hex;
        input [3:0] v;
        to_hex = (v < 10) ? (8'h30 + v) : (8'h37 + v);
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            seq_state <= 0;
            phy_load  <= 0;
            cmd_reg   <= 0;
            pct_reg   <= 0;
        end else begin
            phy_load <= 0;  // default: no load

            case (seq_state)
                0: begin  // IDLE - wait for trigger
                    if (tx_trigger) begin
                        cmd_reg   <= cmd_id;
                        pct_reg   <= percent_val;
                        seq_state <= 1;
                    end
                end
                1: begin  // load CMD byte, wait for PHY idle
                    if (phy_state == 0 && !phy_load) begin
                        phy_data  <= to_hex(cmd_reg);
                        phy_load  <= 1;
                        seq_state <= 2;
                    end
                end
                2: begin  // wait CMD done, then load C_HI
                    if (phy_done) begin
                        phy_data  <= to_hex(pct_reg[6:4]);
                        phy_load  <= 1;
                        seq_state <= 3;
                    end
                end
                3: begin  // wait C_HI done, then load C_LO
                    if (phy_done) begin
                        phy_data  <= to_hex(pct_reg[3:0]);
                        phy_load  <= 1;
                        seq_state <= 4;
                    end
                end
                4: begin  // wait C_LO done, then load LF
                    if (phy_done) begin
                        phy_data  <= 8'h0A;
                        phy_load  <= 1;
                        seq_state <= 5;
                    end
                end
                5: begin  // wait LF done
                    if (phy_done)
                        seq_state <= 0;
                end
                default: seq_state <= 0;
            endcase
        end
    end

endmodule