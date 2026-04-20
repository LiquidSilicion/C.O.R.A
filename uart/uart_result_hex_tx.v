`timescale 1ns / 1ps

module uart_result_hex_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   tx_trigger,
    input  wire [3:0]             cmd_id,
    input  wire signed [16:0]     score_in,
    output wire                   uart_tx,
    output wire                   tx_busy
);

    // Internal signals
    wire [6:0] percent_val;
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;
    reg  [15:0] baud_cnt;
    wire        baud_tick;
    reg  [1:0]  tx_state;
    reg  [7:0]  shift_reg;
    reg  [3:0]  bit_cnt;
    reg         tx_line;
    reg         tx_start;
    reg         tx_done;
    reg  [3:0]  cmd_id_reg;
    reg  [6:0]  percent_reg;
    reg  [7:0]  tx_data_reg;
    reg  [2:0]  seq_state;

    // 1. Score to Percent Converter
    score_percent #(
        .SCORE_WIDTH(17),
        .PERCENT_BITS(7)
    ) u_score_conv (
        .score_in(score_in),
        .percent_out(percent_val)
    );

    // 2. Baud Generator
    assign baud_tick = (baud_cnt == 16'd0);
    always @(posedge clk) begin
        if (!rst_n) baud_cnt <= 16'd0;
        else if (baud_cnt >= BAUD_DIV - 1) baud_cnt <= 16'd0;
        else baud_cnt <= baud_cnt + 16'd1;
    end

    // 3. UART TX PHY
    assign tx_busy = (tx_state != 2'd0);
    assign uart_tx = tx_line;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_state  <= 2'd0;
            tx_line   <= 1'b1;
            bit_cnt   <= 4'd0;
            tx_done   <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            if (tx_start && tx_state == 2'd0) begin
                tx_state  <= 2'd1;
                shift_reg <= tx_data_reg;
                tx_line   <= 1'b0;
                bit_cnt   <= 4'd0;
            end else if (tx_state == 2'd1 && baud_tick) begin
                if (bit_cnt < 4'd8) begin
                    tx_line   <= shift_reg[0];
                    shift_reg <= shift_reg >> 1;
                    bit_cnt   <= bit_cnt + 1;
                end else begin
                    tx_line <= 1'b1;
                    bit_cnt <= bit_cnt + 1;
                    if (bit_cnt == 4'd9) begin
                        tx_state <= 2'd0;
                        bit_cnt  <= 4'd0;
                        tx_done  <= 1'b1;
                    end
                end
            end
        end
    end

    // 4. Data Latch
    always @(posedge clk) begin
        if (!rst_n) begin
            cmd_id_reg  <= 4'd0;
            percent_reg <= 7'd0;
        end else if (tx_trigger && seq_state == 3'd0 && !tx_busy) begin
            cmd_id_reg  <= cmd_id;
            percent_reg <= percent_val;
        end
    end

    // 5. Hex ASCII Function
    function [7:0] nibble_to_hex_ascii;
        input [3:0] val;
        begin
            nibble_to_hex_ascii = (val < 4'd10) ? (val + 8'h30) : (val + 8'h37);
        end
    endfunction

    // 6. Byte Sequencer
    always @(posedge clk) begin
        if (!rst_n) begin
            seq_state <= 3'd0;
            tx_start  <= 1'b0;
        end else if (tx_trigger && seq_state == 3'd0 && !tx_busy) begin
            seq_state   <= 3'd1;
            tx_data_reg <= nibble_to_hex_ascii(cmd_id_reg);
            tx_start    <= 1'b1;
        end else if (tx_done) begin
            tx_start <= 1'b0;
            case (seq_state)
                3'd1: begin
                    tx_data_reg <= nibble_to_hex_ascii(percent_reg[6:4]);
                    seq_state   <= 3'd2; tx_start <= 1'b1;
                end
                3'd2: begin
                    tx_data_reg <= nibble_to_hex_ascii(percent_reg[3:0]);
                    seq_state   <= 3'd3; tx_start <= 1'b1;
                end
                3'd3: begin
                    tx_data_reg <= 8'h0A;
                    seq_state   <= 3'd4; tx_start <= 1'b1;
                end
                3'd4: seq_state <= 3'd5;
                3'd5: seq_state <= 3'd0;
                default: seq_state <= 3'd0;
            endcase
        end
    end

endmodule
