// aer_pipeline.v - Fixed 1-Cycle Read Delay

module aer_pipeline (
    input wire clk,
    input wire rst_n,
    input wire [23:0] aer_data,
    input wire aer_valid,
    
    output wire [3:0] channel_Id,
    output wire [31:0] timestamp,
    output wire timestamp_valid,
    output wire spike_detected,
    output wire window_start,
    output wire fifo_full,
    output wire fifo_empty
);

    wire [23:0] fifo_dout;
    wire fifo_rd_en;
    wire [19:0] raw_timestamp;
    wire raw_ts_valid;
    wire [11:0] rollover_dbg;
    
    // Internal wire for delayed read signal
    reg fifo_rd_valid;

    // FIFO read control: read when not empty
    assign fifo_rd_en = !fifo_empty;

    // ✅ FIX: Delay read signal by 1 cycle to match FIFO output latency
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_rd_valid <= 1'b0;
        end else begin
            fifo_rd_valid <= fifo_rd_en;
        end
    end

    // S7: AER FIFO
    fifo_cdc #(
        .DATA_WIDTH(24),
        .DEPTH(64)
    ) u_aer_fifo (
        .clk(clk),
        .rst(rst_n),
        .wr_en(aer_valid),
        .rd_en(fifo_rd_en),
        .din(aer_data),
        .dout(fifo_dout),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    // S8: AER Decoder (Connected to DELAYED valid signal)
    input_from_aer u_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .in(fifo_dout),
        .aer_valid(fifo_rd_valid),  // <--- USE DELAYED SIGNAL HERE
        .channel_Id(channel_Id),
        .timestamp(raw_timestamp),
        .timestamp_valid(raw_ts_valid),
        .spike_detected(spike_detected)
    );

    // S9: Timestamp Manager
    timestamp_manager u_ts_mgr (
        .clk(clk),
        .rst_n(rst_n),
        .raw_timestamp(raw_timestamp),
        .ts_valid(raw_ts_valid),
        .extended_ts(timestamp),
        .window_start(window_start),
        .rollover_count(rollover_dbg)
    );

endmodule
