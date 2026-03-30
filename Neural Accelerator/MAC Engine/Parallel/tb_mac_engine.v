`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/27/2026 12:08:46 PM
// Design Name: 
// Module Name: tb_mac_engine
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


module tb_mac_engine();
 
    localparam NH         = 128;
    localparam NI         = 16;
    localparam NO         = 10;
    localparam TV         = 1;
    localparam N_PE       = 16;
    localparam GROUPS     = NH / N_PE;
    localparam BRAM_DEPTH = 16'h9800;
 
    localparam W_IN_B  = 16'h0000;
    localparam W_REC_B = 16'h1000;
    localparam W_OUT_B = 16'h9000;
 
    // DUT signals
    reg          clk, rst_n, mac_start;
    wire         mac_done, score_valid;
    wire [15:0]  x_raddr;
    wire         x_ren;
    wire [7:0]   x_rdata;
    wire [N_PE*16-1:0] w_raddr_flat;
    wire [N_PE*16-1:0] w_rdata_flat;
    wire         w_ren;
    wire [15:0]  lif_acc;
    wire [6:0]   lif_idx;
    wire         lif_wen, lif_capture;
    reg  [NH-1:0] lif_spikes;
    wire [NO*32-1:0] score_out;
 
    // ========================================================================
    // EXTERNAL BRAM MODELS - Combinational read (0-cycle latency)
    // Matches DUT expectation: address → data in same cycle
    // ========================================================================
    reg [15:0] wbram [0:BRAM_DEPTH-1];
    reg [N_PE*16-1:0] w_rdata_flat_r;
    integer p;
    
    always @(*) begin
        for (p=0; p<N_PE; p=p+1)
            w_rdata_flat_r[p*16 +: 16] = wbram[w_raddr_flat[p*16 +: 16]];
    end
    assign w_rdata_flat = w_rdata_flat_r;
 
    reg [7:0] xbram [0:TV*NI-1];
    reg [7:0] x_rdata_r;
    always @(*) x_rdata_r = xbram[x_raddr];
    assign x_rdata = x_rdata_r;
 
    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    mac_engine #(
        .NH(NH), .NI(NI), .NO(NO), .T(TV), .N_PE(N_PE),
        .W_IN_BASE(W_IN_B), .W_REC_BASE(W_REC_B), .W_OUT_BASE(W_OUT_B)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .mac_start(mac_start), .mac_done(mac_done),
        .x_raddr(x_raddr), .x_ren(x_ren), .x_rdata(x_rdata),
        .w_raddr_flat(w_raddr_flat), .w_rdata_flat(w_rdata_flat), .w_ren(w_ren),
        .lif_acc(lif_acc), .lif_idx(lif_idx),
        .lif_wen(lif_wen), .lif_capture(lif_capture),
        .lif_spikes(lif_spikes),
        .score_out(score_out), .score_valid(score_valid)
    );
 
    // ========================================================================
    // BRAM Initialization - Pattern from tb_s11_v2.v
    // ========================================================================
    integer bi;
    initial begin
        // Zero all BRAM first
        for (bi=0; bi<BRAM_DEPTH; bi=bi+1) wbram[bi] = 16'h0000;
        
        // W_IN: neurons 0,1 receive input (others = 0)
        for (bi=0; bi<NI; bi=bi+1) begin
            wbram[W_IN_B + 0*NI + bi] = 16'h0100;
            wbram[W_IN_B + 1*NI + bi] = 16'h0100;
        end
        
        // W_REC: self-feedback only for neurons 0,1
        wbram[W_REC_B + 0*NH + 0] = 16'h0100;
        wbram[W_REC_B + 1*NH + 1] = 16'h0100;
        wbram[W_REC_B + 2*NH + 2] = 16'h0000;  // Explicit zero
        
        // W_OUT: neurons 0,1 connect to all outputs
        for (bi=0; bi<NO; bi=bi+1) begin
            wbram[W_OUT_B + 0*NO + bi] = 16'h0100;
            wbram[W_OUT_B + 1*NO + bi] = 16'h0100;
            wbram[W_OUT_B + 2*NO + bi] = 16'h0000;  // Explicit zero
        end
    end
 
    initial begin
        for (bi=0; bi<TV*NI; bi=bi+1) xbram[bi] = 8'd0;
        xbram[0] = 8'd2;  // Input spike strength
        xbram[1] = 8'd3;
    end
 
    // ========================================================================
    // LIF Model - No leak, threshold = 0x0100 (Q8.8 = 1.0)
    // ========================================================================
    reg [15:0] vm [0:NH-1];
    integer li;
    initial begin
        lif_spikes = {NH{1'b0}};
        for (li=0; li<NH; li=li+1) vm[li] = 16'd0;
    end
    
    always @(posedge clk) begin
        if (lif_wen)
            vm[lif_idx] <= vm[lif_idx] + lif_acc;
        if (lif_capture) begin
            for (li=0; li<NH; li=li+1) begin
                if (vm[li] >= 16'h0100) begin
                    lif_spikes[li] <= 1'b1;
                    vm[li]         <= 16'd0;
                end else
                    lif_spikes[li] <= 1'b0;
            end
        end
    end
 
    // Clock: 100MHz
    initial clk = 0;
    always #5 clk = ~clk;
 
    // ========================================================================
    // Test Infrastructure - Pattern from tb_s11_v2.v
    // ========================================================================
    integer fail_count;
    task check;
        input [127:0] label;
        input [63:0]  exp, got;
        begin
            if (exp === got)
                $display("[PASS]  %-28s  exp=0x%08h  got=0x%08h", label, exp, got);
            else begin
                $display("[FAIL]  %-28s  exp=0x%08h  got=0x%08h", label, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask
 
    reg     got_done;
    integer cyc, j;
 
    initial begin
        fail_count = 0;
        mac_start = 0; rst_n = 0;
        lif_spikes = {NH{1'b0}};
        
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1;
 
        // TC1: Verify weight BRAM initialization
        $display("--- TC1: weight BRAM ---");
        check("W_in[0][0]=1.0",  16'h0100, wbram[W_IN_B + 0*NI + 0]);
        check("W_in[1][1]=1.0",  16'h0100, wbram[W_IN_B + 1*NI + 1]);
        check("W_rec[0][0]=1.0", 16'h0100, wbram[W_REC_B + 0*NH + 0]);
        check("W_rec[1][1]=1.0", 16'h0100, wbram[W_REC_B + 1*NH + 1]);
        check("W_rec[2][2]=0",   16'h0000, wbram[W_REC_B + 2*NH + 2]);
        check("W_out[0][0]=1.0", 16'h0100, wbram[W_OUT_B + 0*NO + 0]);
        check("W_out[1][9]=1.0", 16'h0100, wbram[W_OUT_B + 1*NO + 9]);
        check("W_out[2][0]=0",   16'h0000, wbram[W_OUT_B + 2*NO + 0]);
 
        // TC2: mac_start exits IDLE
        $display("--- TC2: mac_start ---");
        @(negedge clk); mac_start = 1;
        @(posedge clk); #1; mac_start = 0;
        @(posedge clk); #1;
        check("FSM not IDLE", 1, (dut.state != 4'd0));
 
        // TC3-TC5: Forward pass
        $display("--- TC3-TC5: forward pass ---");
        got_done = 0;
        for (cyc=0; cyc<20000 && !got_done; cyc=cyc+1) begin
            @(posedge clk); #1;
            if (mac_done) got_done = 1;
        end
        check("mac_done fired", 1, got_done);
        check("score_valid",    1, score_valid);
 
        // TC6: Verify scores
        $display("--- TC6: scores ---");
        for (j=0; j<NO; j=j+1)
            check("score[j]=0x00020000", 32'h00020000, score_out[j*32+:32]);
 
        // TC7: Verify LIF spikes
        $display("--- TC7: LIF spikes ---");
        check("s_prev[0] fired",   1, dut.s_prev[0]);
        check("s_prev[1] fired",   1, dut.s_prev[1]);
        check("s_prev[2] quiet",   0, dut.s_prev[2]);  // <<< Critical test
        check("s_prev[127] quiet", 0, dut.s_prev[127]);
 
        // TC8: Second run - verify clean state
        $display("--- TC8: second run (clean state) ---");
        // Reset LIF membrane potentials between runs (inspired by tb_s11_v2)
        for (li=0; li<NH; li=li+1) vm[li] = 16'd0;
        lif_spikes = {NH{1'b0}};
        
        @(negedge clk); mac_start = 1;
        @(posedge clk); #1; mac_start = 0;
        got_done = 0;
        for (cyc=0; cyc<20000 && !got_done; cyc=cyc+1) begin
            @(posedge clk); #1;
            if (mac_done) got_done = 1;
        end
        check("mac_done again", 1, got_done);
        for (j=0; j<NO; j=j+1)
            check("score[j]=2 again", 32'h00020000, score_out[j*32+:32]);
        check("s_prev[2] still quiet", 0, dut.s_prev[2]);  // <<< Verify fix
 
        @(posedge clk); #1;
        if (fail_count == 0)
            $display("\n✅ ALL TESTS PASSED");
        else
            $display("\n❌ TESTS COMPLETED - %0d FAILURE(S)", fail_count);
        $finish;
    end
 
    // Timeout guard
    initial begin #5000000; $display("[FAIL] TIMEOUT"); $finish; end
 
endmodule