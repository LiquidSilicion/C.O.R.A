module tb_mac_engine();

    localparam NH = 2;
    localparam NI = 4;
    localparam NO = 2;
    localparam TV = 3;

    localparam W_IN_B  = 16'h0000;
    localparam W_REC_B = 16'h0008;   // 2*4 = 8
    localparam W_OUT_B = 16'h000C;   // 8 + 2*2 = 12

    // ── DUT signals ──────────────────────────────────────────────────────────
    reg         clk, rst_n, mac_start;
    wire        mac_done;
    wire [15:0] x_raddr, w_raddr;
    wire        x_ren, w_ren;
    wire [15:0] lif_acc;
    wire [6:0]  lif_idx;
    wire        lif_wen, lif_capture;
    reg  [NH-1:0] lif_spikes;
    wire [NO*32-1:0] score_out;
    wire        score_valid;

    // ── Combinational BRAM models (zero latency - no race) ───────────────────
    // w_rdata driven combinationally from address
    reg  [15:0] wbram [0:31];
    wire [15:0] w_rdata = w_ren ? wbram[w_raddr[4:0]] : 16'h0000;

    // x_rdata driven combinationally from address
    reg  [7:0]  xbram [0:TV*NI-1];
    wire [7:0]  x_rdata = x_ren ? xbram[x_raddr[3:0]] : 8'h00;

    // ── DUT ──────────────────────────────────────────────────────────────────
    mac_engine #(
        .NH(NH), .NI(NI), .NO(NO), .T(TV),
        .W_IN_BASE(W_IN_B), .W_REC_BASE(W_REC_B), .W_OUT_BASE(W_OUT_B)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .mac_start(mac_start), .mac_done(mac_done),
        .x_raddr(x_raddr), .x_ren(x_ren), .x_rdata(x_rdata),
        .w_raddr(w_raddr), .w_ren(w_ren), .w_rdata(w_rdata),
        .lif_acc(lif_acc), .lif_idx(lif_idx),
        .lif_wen(lif_wen), .lif_capture(lif_capture),
        .lif_spikes(lif_spikes),
        .score_out(score_out), .score_valid(score_valid)
    );

    // ── Weight BRAM initialisation ────────────────────────────────────────────
    integer bi;
    initial begin
        for (bi=0; bi<32; bi=bi+1) wbram[bi] = 16'h0000;
        // W_in row 0: {1,0,0,0}  (addr 0x00..0x03)
        wbram[0] = 16'h0100;  // W_in[0][0] = 1.0
        wbram[1] = 16'h0000;
        wbram[2] = 16'h0000;
        wbram[3] = 16'h0000;
        // W_in row 1: {0,1,0,0}  (addr 0x04..0x07)
        wbram[4] = 16'h0000;
        wbram[5] = 16'h0100;  // W_in[1][1] = 1.0
        wbram[6] = 16'h0000;
        wbram[7] = 16'h0000;
        // W_rec [2×2]: all zero  (addr 0x08..0x0B)
        // W_out identity  (addr 0x0C..0x0F)
        wbram[12] = 16'h0100; // W_out[0][0] = 1.0
        wbram[13] = 16'h0000;
        wbram[14] = 16'h0000;
        wbram[15] = 16'h0100; // W_out[1][1] = 1.0
    end

    // ── Window BRAM initialisation ────────────────────────────────────────────
    initial begin
        xbram[0]=8'd2; xbram[1]=8'd0; xbram[2]=8'd0; xbram[3]=8'd0; // t=0
        xbram[4]=8'd0; xbram[5]=8'd3; xbram[6]=8'd0; xbram[7]=8'd0; // t=1
        xbram[8]=8'd1; xbram[9]=8'd1; xbram[10]=8'd0; xbram[11]=8'd0; // t=2
    end

    // ── LIF array model ───────────────────────────────────────────────────────
    // No leak (simplified). Fires when V_m >= 1.0 (Q8.8 = 0x0100).
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

    initial clk = 0;
    always #5 clk = ~clk;

    integer fail_count;

    task check;
        input [127:0] label;
        input [63:0]  exp, got;
        begin
            if (exp === got)
                $display("[PASS] %s  exp=0x%08h  got=0x%08h", label, exp, got);
            else begin
                $display("[FAIL] %s  exp=0x%08h  got=0x%08h", label, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    reg     got_done;
    integer cyc;

    initial begin
        fail_count = 0;
        mac_start  = 0;
        lif_spikes = {NH{1'b0}};
        rst_n    = 0;

        repeat(4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1;

        // ── TC1: weight BRAM spot check ───────────────────────────────────
        $display("--- TC1: weight BRAM ---");
        check("TC1 W_in[0][0] =1.0", 16'h0100, wbram[0]);
        check("TC1 W_in[1][1] =1.0", 16'h0100, wbram[5]);
        check("TC1 W_out[0][0]=1.0", 16'h0100, wbram[12]);
        check("TC1 W_out[1][1]=1.0", 16'h0100, wbram[15]);
        check("TC1 W_rec[0][0]=0  ", 16'h0000, wbram[8]);

        // ── TC2: mac_start exits IDLE ─────────────────────────────────────
        $display("--- TC2: mac_start ---");
        @(negedge clk); mac_start = 1;
        @(posedge clk); #1; mac_start = 0;
        @(posedge clk); #1;
        check("TC2 FSM not IDLE   ", 1, (dut.state != 4'd0));

        // ── TC3-TC6: run full forward pass ────────────────────────────────
        $display("--- TC3-TC6: forward pass ---");
        got_done = 0;
        for (cyc=0; cyc<5000 && !got_done; cyc=cyc+1) begin
            @(posedge clk); #1;
            if (mac_done) got_done = 1;
        end

        // ── TC5: completion ───────────────────────────────────────────────
        check("TC5 mac_done fired ", 1,           got_done);
        check("TC5 score_valid    ", 1,           score_valid);

        // ── TC6: golden reference ─────────────────────────────────────────
        $display("--- TC6: scores ---");
        check("TC6 score[0]=2     ", 32'h00020000, score_out[0*32+:32]);
        check("TC6 score[1]=2     ", 32'h00020000, score_out[1*32+:32]);

        // ── TC4: LIF fired ────────────────────────────────────────────────
        check("TC4 s_prev != 0   ", 1, (dut.s_prev != 0));

        // ── TC7: second run produces same result ──────────────────────────
        $display("--- TC7: second run ---");
        @(negedge clk); mac_start = 1;
        @(posedge clk); #1; mac_start = 0;
        got_done = 0;
        for (cyc=0; cyc<5000 && !got_done; cyc=cyc+1) begin
            @(posedge clk); #1;
            if (mac_done) got_done = 1;
        end
        check("TC7 mac_done again ", 1,           got_done);
        check("TC7 score[0]=2     ", 32'h00020000, score_out[0*32+:32]);
        check("TC7 score[1]=2     ", 32'h00020000, score_out[1*32+:32]);

        // ── Summary ───────────────────────────────────────────────────────
        @(posedge clk); #1;
        if (fail_count == 0)
            $display("ALL TESTS PASSED (%0d failures)", fail_count);
        else
            $display("TESTS COMPLETED - %0d FAILURE(S)", fail_count);
        $finish;
    end

    initial begin #2000000; $display("[FAIL] TIMEOUT"); $finish; end

endmodule
