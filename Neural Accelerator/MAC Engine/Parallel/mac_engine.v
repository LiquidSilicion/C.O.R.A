`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/23/2026 07:08:27 PM
// Design Name: 
// Module Name: mac_engine
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

module mac_engine #(
    parameter NH         = 128,
    parameter NI         = 16,
    parameter NO         = 10,
    parameter T          = 50,
    parameter N_PE       = 16,
    parameter W_IN_BASE  = 16'h0000,
    parameter W_REC_BASE = 16'h1000,
    parameter W_OUT_BASE = 16'h9000
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   mac_start,
    output reg                    mac_done,
 
    output reg  [15:0]            x_raddr,
    output reg                    x_ren,
    input  wire [7:0]             x_rdata,
 
    output reg  [N_PE*16-1:0]     w_raddr_flat,
    input  wire [N_PE*16-1:0]     w_rdata_flat,
    output reg                    w_ren,
 
    output reg  [15:0]            lif_acc,
    output reg  [6:0]             lif_idx,
    output reg                    lif_wen,
    output reg                    lif_capture,
    input  wire [NH-1:0]          lif_spikes,
 
    output reg  [NO*32-1:0]       score_out,
    output reg                    score_valid
);
 
    localparam GROUPS = NH / N_PE;
    localparam [3:0]
        S_IDLE    = 4'd0, S_LOAD_X  = 4'd1, S_W_IN    = 4'd2,
        S_W_REC   = 4'd3, S_LIF_UPD = 4'd4, S_W_OUT   = 4'd5,
        S_NEXT_T  = 4'd6, S_DONE    = 4'd7;
    localparam [1:0] PH_WIN=2'd0, PH_WREC=2'd1, PH_WOUT=2'd2;
 
    reg [3:0]    state;
    reg [5:0]    t_cnt;
    reg [7:0]    group_cnt, col_cnt, lif_cnt;
    reg [31:0]   acc   [0:NH-1];
    reg [31:0]   score [0:NO-1];
    reg [NH-1:0] s_prev;
 
    // Pipeline registers for MAC stage
    reg        p0_en, p1_en;
    reg [1:0]  p0_ph, p1_ph;
    reg [7:0]  p0_group, p1_group, p0_col, p1_col;
    reg [15:0] p0_wdata [0:N_PE-1], p1_wdata [0:N_PE-1];
    reg [15:0] p0_xop   [0:N_PE-1], p1_xop   [0:N_PE-1];
 
    // MAC + Reduction
    wire signed [31:0] mac_res [0:N_PE-1];
    genvar gv;
    generate
        for (gv=0; gv<N_PE; gv=gv+1) begin : gen_mac
            assign mac_res[gv] = $signed(p1_wdata[gv]) * $signed(p1_xop[gv]);
        end
    endgenerate
 
    wire signed [31:0] pe_sum [0:N_PE];
    assign pe_sum[0] = 32'sd0;
    generate
        for (gv=0; gv<N_PE; gv=gv+1) begin : gen_pesum
            assign pe_sum[gv+1] = pe_sum[gv] + mac_res[gv];
        end
    endgenerate
    wire signed [31:0] pe_total = pe_sum[N_PE];
 
    // Output assignment
    integer pi;
    always @(*) begin
        for (pi=0; pi<NO; pi=pi+1)
            score_out[pi*32 +: 32] = score[pi];
    end
 
    // Address calculation helper
    function [15:0] waddr;
        input [15:0] base;
        input [7:0]  row, col, stride;
        begin waddr = base + row * stride + col; end
    endfunction
 
    integer ri, k;
 
    always @(posedge clk) begin
        if (!rst_n) begin
            // Full reset
            state <= S_IDLE; t_cnt <= 0; group_cnt <= 0; col_cnt <= 0; lif_cnt <= 0;
            mac_done <= 0; score_valid <= 0;
            w_ren <= 0; w_raddr_flat <= 0;
            x_ren <= 0; x_raddr <= 0;
            lif_wen <= 0; lif_capture <= 0; lif_acc <= 0; lif_idx <= 0;
            p0_en <= 0; p0_ph <= 0; p0_group <= 0; p0_col <= 0;
            p1_en <= 0; p1_ph <= 0; p1_group <= 0; p1_col <= 0;
            s_prev <= 0;
            for (ri=0; ri<NH; ri=ri+1) acc[ri]   <= 0;
            for (ri=0; ri<NO; ri=ri+1) score[ri] <= 0;
            for (k=0; k<N_PE; k=k+1) begin
                p0_wdata[k] <= 0; p0_xop[k] <= 0;
                p1_wdata[k] <= 0; p1_xop[k] <= 0;
            end
        end else begin
            // Default de-assertions
            mac_done <= 0; score_valid <= 0;
            w_ren <= 0; x_ren <= 0; lif_wen <= 0; lif_capture <= 0;
 
            // Pipeline shift
            p1_en    <= p0_en;
            p1_ph    <= p0_ph;
            p1_group <= p0_group;
            p1_col   <= p0_col;
            for (k=0; k<N_PE; k=k+1) begin
                p1_wdata[k] <= p0_wdata[k];
                p1_xop[k]   <= p0_xop[k];
            end
 
            // Accumulate results from executed MAC cycle
            if (p1_en) begin
                case (p1_ph)
                    PH_WIN, PH_WREC: begin
                        for (k=0; k<N_PE; k=k+1)
                            acc[p1_group*N_PE + k] <= acc[p1_group*N_PE + k] + mac_res[k];
                    end
                    PH_WOUT: begin
                        score[p1_col] <= score[p1_col] + pe_total;
                    end
                endcase
            end
            p0_en <= 0;
 
            // FSM
            case (state)
                S_IDLE: begin
                    if (mac_start) begin
                        t_cnt <= 0;
                        for (ri=0; ri<NO; ri=ri+1) score[ri] <= 0;
                        s_prev <= 0;  // <<< FIX: Reset recurrent state per window
                        state <= S_LOAD_X;
                    end
                end
 
                S_LOAD_X: begin
                    for (ri=0; ri<NH; ri=ri+1) acc[ri] <= 0;
                    for (k=0; k<N_PE; k=k+1)
                        w_raddr_flat[k*16 +: 16] <= waddr(W_IN_BASE, k, 8'd0, NI);
                    w_ren <= 1; x_raddr <= t_cnt * NI; x_ren <= 1;
                    group_cnt <= 0; col_cnt <= 0;
                    state <= S_W_IN;
                end
 
                S_W_IN: begin
                    p0_en <= 1; p0_ph <= PH_WIN;
                    p0_group <= group_cnt; p0_col <= col_cnt;
                    for (k=0; k<N_PE; k=k+1) begin
                        p0_wdata[k] <= w_rdata_flat[k*16 +: 16];
                        p0_xop[k]   <= {x_rdata, 8'd0};  // Q8.8 extension
                    end
                    if (group_cnt == GROUPS-1) begin
                        if (col_cnt == NI-1) begin
                            for (k=0; k<N_PE; k=k+1)
                                w_raddr_flat[k*16 +: 16] <= waddr(W_REC_BASE, k, 8'd0, NH);
                            w_ren <= 1; group_cnt <= 0; col_cnt <= 0;
                            state <= S_W_REC;
                        end else begin
                            for (k=0; k<N_PE; k=k+1)
                                w_raddr_flat[k*16 +: 16] <= waddr(W_IN_BASE, k, col_cnt+1, NI);
                            w_ren <= 1; x_raddr <= t_cnt*NI + (col_cnt+1); x_ren <= 1;
                            group_cnt <= 0; col_cnt <= col_cnt+1;
                        end
                    end else begin
                        for (k=0; k<N_PE; k=k+1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_IN_BASE, (group_cnt+1)*N_PE + k, col_cnt, NI);
                        w_ren <= 1; x_raddr <= t_cnt*NI + col_cnt; x_ren <= 1;
                        group_cnt <= group_cnt+1;
                    end
                end
 
                S_W_REC: begin
                    p0_en <= 1; p0_ph <= PH_WREC;
                    p0_group <= group_cnt; p0_col <= col_cnt;
                    for (k=0; k<N_PE; k=k+1) begin
                        p0_wdata[k] <= w_rdata_flat[k*16 +: 16];
                        p0_xop[k]   <= s_prev[col_cnt] ? 16'h0100 : 16'h0000;
                    end
                    if (group_cnt == GROUPS-1) begin
                        if (col_cnt == NH-1) begin
                            group_cnt <= 0; col_cnt <= 0; lif_cnt <= 0;
                            state <= S_LIF_UPD;
                        end else begin
                            for (k=0; k<N_PE; k=k+1)
                                w_raddr_flat[k*16 +: 16] <= waddr(W_REC_BASE, k, col_cnt+1, NH);
                            w_ren <= 1; group_cnt <= 0; col_cnt <= col_cnt+1;
                        end
                    end else begin
                        for (k=0; k<N_PE; k=k+1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_REC_BASE, (group_cnt+1)*N_PE + k, col_cnt, NH);
                        w_ren <= 1; group_cnt <= group_cnt+1;
                    end
                end
 
                S_LIF_UPD: begin
                    if (lif_cnt == 0) begin
                        lif_cnt <= 1;
                    end else if (lif_cnt <= NH) begin
                        lif_acc <= acc[lif_cnt-1][23:8];
                        lif_idx <= lif_cnt - 1;  // <<< FIX: Remove [6:0] bit-slice
                        lif_wen <= 1;
                        lif_cnt <= lif_cnt + 1;
                    end else if (lif_cnt == NH+1) begin
                        lif_capture <= 1;
                        lif_cnt <= lif_cnt + 1;
                    end else if (lif_cnt == NH+2) begin
                        lif_cnt <= lif_cnt + 1;
                    end else begin
                        s_prev <= lif_spikes;
                        group_cnt <= 0; col_cnt <= 0; lif_cnt <= 0;
                        for (k=0; k<N_PE; k=k+1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_OUT_BASE, k, 8'd0, NO);
                        w_ren <= 1;
                        state <= S_W_OUT;
                    end
                end
 
                S_W_OUT: begin
                    p0_en <= 1; p0_ph <= PH_WOUT;
                    p0_group <= group_cnt; p0_col <= col_cnt;
                    for (k=0; k<N_PE; k=k+1) begin
                        p0_wdata[k] <= w_rdata_flat[k*16 +: 16];
                        p0_xop[k]   <= s_prev[group_cnt*N_PE + k] ? 16'h0100 : 16'h0000;
                    end
                    if (group_cnt == GROUPS-1) begin
                        if (col_cnt == NO-1) begin
                            group_cnt <= 0; col_cnt <= 0;
                            state <= S_NEXT_T;
                        end else begin
                            for (k=0; k<N_PE; k=k+1)
                                w_raddr_flat[k*16 +: 16] <= waddr(W_OUT_BASE, k, col_cnt+1, NO);
                            w_ren <= 1; group_cnt <= 0; col_cnt <= col_cnt+1;
                        end
                    end else begin
                        for (k=0; k<N_PE; k=k+1)
                            w_raddr_flat[k*16 +: 16] <= waddr(W_OUT_BASE, (group_cnt+1)*N_PE + k, col_cnt, NO);
                        w_ren <= 1; group_cnt <= group_cnt+1;
                    end
                end
 
                S_NEXT_T: begin
                    if (t_cnt == T-1) state <= S_DONE;
                    else begin t_cnt <= t_cnt+1; state <= S_LOAD_X; end
                end
 
                S_DONE: begin
                    mac_done <= 1; score_valid <= 1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule