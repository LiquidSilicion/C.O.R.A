module aer_encoder_pro (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sample_en,
    input  wire [15:0] spike,

    output reg  [23:0] data,
    output reg         aer_valid,
    input  wire        aer_ready
);

    // ----------------------------------------------------------
    //  Timestamp (increments per sample)
    // ----------------------------------------------------------
    reg [19:0] timestamp;

    always @(posedge clk) begin
        if (!rst_n)
            timestamp <= 20'd0;
        else if (sample_en)
            timestamp <= timestamp + 1'd1;
    end

    // ----------------------------------------------------------
    //  Latched timestamp (for current burst)
    // ----------------------------------------------------------
    reg [19:0] ts_latch;

    always @(posedge clk) begin
        if (!rst_n)
            ts_latch <= 20'd0;
        else if (sample_en)
            ts_latch <= timestamp + 1'd1;
    end

    // ----------------------------------------------------------
    //  Spike accumulator (CRITICAL: prevents loss)
    // ----------------------------------------------------------
    reg [15:0] spike_reg;

    always @(posedge clk) begin
        if (!rst_n)
            spike_reg <= 16'd0;
        else begin
            // Always accumulate incoming spikes
            spike_reg <= spike_reg | spike;

            // Clear bit ONLY when successfully transmitted
            if (send_fire)
                spike_reg[ch_id] <= 1'b0;
        end
    end

    // ----------------------------------------------------------
    //  Priority encoder (find lowest set bit)
    // ----------------------------------------------------------
    reg [3:0] ch_id;
    reg       found;

    always @(*) begin
        found = 1'b0;
        ch_id = 4'd0;

        if      (spike_reg[0])  begin found=1'b1; ch_id=4'd0;  end
        else if (spike_reg[1])  begin found=1'b1; ch_id=4'd1;  end
        else if (spike_reg[2])  begin found=1'b1; ch_id=4'd2;  end
        else if (spike_reg[3])  begin found=1'b1; ch_id=4'd3;  end
        else if (spike_reg[4])  begin found=1'b1; ch_id=4'd4;  end
        else if (spike_reg[5])  begin found=1'b1; ch_id=4'd5;  end
        else if (spike_reg[6])  begin found=1'b1; ch_id=4'd6;  end
        else if (spike_reg[7])  begin found=1'b1; ch_id=4'd7;  end
        else if (spike_reg[8])  begin found=1'b1; ch_id=4'd8;  end
        else if (spike_reg[9])  begin found=1'b1; ch_id=4'd9;  end
        else if (spike_reg[10]) begin found=1'b1; ch_id=4'd10; end
        else if (spike_reg[11]) begin found=1'b1; ch_id=4'd11; end
        else if (spike_reg[12]) begin found=1'b1; ch_id=4'd12; end
        else if (spike_reg[13]) begin found=1'b1; ch_id=4'd13; end
        else if (spike_reg[14]) begin found=1'b1; ch_id=4'd14; end
        else if (spike_reg[15]) begin found=1'b1; ch_id=4'd15; end
    end

    // ----------------------------------------------------------
    //  Handshake logic
    // ----------------------------------------------------------
    wire send_fire;

    assign send_fire = found && (aer_ready || !aer_valid);

    // ----------------------------------------------------------
    //  Output logic
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            data      <= 24'd0;
            aer_valid <= 1'b0;
        end else begin

            if (send_fire) begin
                // Send packet
                data      <= {ch_id, ts_latch};
                aer_valid <= 1'b1;
            end else if (aer_ready) begin
                // Clear valid when consumed and nothing new
                aer_valid <= 1'b0;
            end
        end
    end

endmodule
