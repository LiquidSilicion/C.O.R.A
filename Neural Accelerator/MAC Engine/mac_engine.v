module mac_engine #(
    
    parameter NH = 8, //hidden neurons
    parameter NI = 16, //cochlea channels
    parameter NO = 10, //command classes
    parameter T = 50, //timesteps per window
    parameter W_IN_BASE = 16'h0000, //
    parameter W_REC_BASE = 16'h0800,
    parameter W_OUT_BASE = 16'h4800
)(  
    input clk,
    input rst_n,
    input  mac_start,
    output reg mac_done,
    output reg x_raddr,
    output reg x_ren,
    input  wire [7:0]  x_rdata,
    
    input wire [15:0] w_rdata,
    output w_ren,
    input  wire [15:0] w_rdata,
    
    output [15:0] lif_acc,
    output [6:0] lif_idx,
    output reg lif_wen,
    output reg lif_capture,
    input [NH-1:0] lif_spikes,
    
    output reg [NO*32-1:0] score_out,
    output reg score_valid);
    
   localparam [3:0]
   S_IDLE    = 4'd0,
   S_LOAD_X  = 4'd1,
   S_W_IN    = 4'd2,
   S_W_REC   = 4'd3,
   S_LIF_UPD = 4'd4,
   S_W_OUT   = 4'd5,
   S_NEXT_T  = 4'd6,
   S_DONE    = 4'd7;
   
   localparam [1:0] PH_WIN=0, PH_WREC=1, PH_WOUT=2;
 
    reg [3:0]  state;
    reg [5:0]  t_cnt;
    reg [7:0]  n_cnt, col_cnt, lif_cnt;
 
    reg [31:0] acc   [0:NH-1];
    reg [31:0] score [0:NO-1];
    reg [NH-1:0] s_prev;
    reg [7:0]  p1_n, p1_col;
    reg [1:0]  p1_ph;
    reg p1_en;
    reg [15:0] p1_x;
    
    
    wire [15:0] exec_x = (p1_ph == PH_WIN) ? {x_rdata, 8'd0} : p1_x;
    wire signed [31:0] mac_res = $signed(w_rdata) * $signed(exec_x);
    
    
        function [15:0] waddr;
        input [15:0] base; input [7:0] n, col, stride;
        begin waddr = base + n * stride + col; end
    endfunction
 
    integer pi;
    always @(*) begin
        for (pi=0; pi<NO; pi=pi+1)
            score_out[pi*32 +: 32] = score[pi];
    end
 
    integer ri;
 
    always @(posedge clk) begin
        if (!reset_n) begin
            state<=S_IDLE; t_cnt<=0; n_cnt<=0; col_cnt<=0; lif_cnt<=0;
            mac_done<=0; score_valid<=0;
            w_ren<=0; x_ren<=0; lif_wen<=0; lif_capture<=0;
            p1_en<=0; p1_n<=0; p1_col<=0; p1_ph<=0; p1_x<=0;
            s_prev<=0;
            for(ri=0;ri<NH;ri=ri+1) acc[ri]   <=0;
            for(ri=0;ri<NO;ri=ri+1) score[ri] <=0;
        end else begin
 
            mac_done<=0; score_valid<=0;
            w_ren<=0; x_ren<=0; lif_wen<=0; lif_capture<=0;
endmodule
