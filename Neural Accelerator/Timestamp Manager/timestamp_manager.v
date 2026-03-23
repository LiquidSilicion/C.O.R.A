module timestamp_manager(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [19:0] timestamp,
    input  wire        ts_valid,
    input  wire        window_open,
    output reg  [31:0] ts_abs,
    output reg         ts_abs_valid,
    output reg  [31:0] window_start,
    output reg  [19:0] window_offset
);
 
    reg [19:0] ts_prev;
    reg [11:0] rollover_count;
 
    wire [31:0] ts_abs_comb;
    assign ts_abs_comb = {rollover_count, timestamp};
 
    wire [31:0] offset_full;
    assign offset_full = ts_abs_comb - window_start;
 
    wire rollover_detected;
    assign rollover_detected = ts_valid && (ts_prev > timestamp) && ((ts_prev - timestamp) > 20'h80000);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rollover_count <= 12'd0;
            ts_prev        <= 20'd0;
        end else if (ts_valid) begin
            if (rollover_detected)
                rollover_count <= rollover_count + 12'd1;
            ts_prev <= timestamp; 
        end
    end
 
    always @(posedge clk) begin
        if (!rst_n) begin
            ts_abs       <= 32'd0;
            ts_abs_valid <= 1'b0;
        end else begin
            ts_abs_valid <= ts_valid;
            if (ts_valid) begin
                if (rollover_detected)
                    ts_abs <= {rollover_count + 12'd1, timestamp};
                else
                    ts_abs <= {rollover_count, timestamp};
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_start  <= 32'd0;
            window_offset <= 20'd0;
        end else begin
            if (window_open)
                window_start <= ts_abs_comb;
            if (ts_valid) begin
                if (offset_full[31:20] != 12'd0)
                    window_offset <= 20'hFFFFF;
                else
                    window_offset <= offset_full[19:0];
            end
        end
    end
