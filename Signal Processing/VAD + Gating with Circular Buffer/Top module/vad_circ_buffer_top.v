module vad_circ_buffer_top #(
    parameter SAMPLE_RATE          = 16000,
    parameter CLK_FREQ             = 100000000,
    parameter THRESHOLD_ON         = 32'd2000000,
    parameter THRESHOLD_OFF        = 32'd1000000,
    parameter THRESHOLD_ADAPT_RATE = 4,
    parameter ZCR_MIN_SPEECH       = 15,
    parameter ZCR_MAX_SPEECH       = 45,
    parameter HANGOVER_MS          = 300,
    parameter WINDOW_MS            = 10,
    parameter BUFFER_SIZE          = 24000,
    parameter PRE_TRIGGER_SAMPLES  = 3200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] audio_in,
    input  wire        sample_valid,
    output wire [15:0] audio_out,
    output wire        audio_valid,
    output wire        speech_valid,
    output wire [31:0] smoothed_energy,
    output wire [31:0] noise_floor,
    output wire [15:0] zero_cross_rate
);
    // ─────────────────────────────────────────────────────────────────────
    // Internal FSM 1 Registers & Parameters
    // ─────────────────────────────────────────────────────────────────────
    reg [1:0]  state, next_state;
    reg [11:0] pretrig_cnt;
    reg [13:0] hangover_ctr;
    reg        pre_trig_rewind;
    reg        rd_en;
    reg        speech_valid_r; // Drives the output wire safely

    parameter HANGOVER_CYCLES = SAMPLE_RATE * HANGOVER_MS / 1000;
    parameter ADDR_WIDTH      = 15;
    localparam ST_IDLE     = 2'b00;
    localparam ST_PRETRIG  = 2'b01;
    localparam ST_ACTIVE   = 2'b10;
    localparam ST_HANGOVER = 2'b11;

    // ─────────────────────────────────────────────────────────────────────
    // Internal Wires
    // ─────────────────────────────────────────────────────────────────────
    wire speech_detected;
    wire pre_trigger_pulse;
    wire data_valid;
    wire [15:0] data_out;

    // ─────────────────────────────────────────────────────────────────────
    // Output Assignments
    // ─────────────────────────────────────────────────────────────────────
    assign audio_out    = data_out;
    assign audio_valid  = data_valid;       // combinational data_valid already gated with rd_en
    assign speech_valid = speech_valid_r;

    // ─────────────────────────────────────────────────────────────────────
    // 1. VAD Instantiation (S1)
    // ─────────────────────────────────────────────────────────────────────
    vad #(
        .SAMPLE_RATE(SAMPLE_RATE),
        .CLK_FREQ(CLK_FREQ),
        .THRESHOLD_ON(THRESHOLD_ON),
        .THRESHOLD_OFF(THRESHOLD_OFF),
        .THRESHOLD_ADAPT_RATE(THRESHOLD_ADAPT_RATE),
        .ZCR_MIN_SPEECH(ZCR_MIN_SPEECH),
        .ZCR_MAX_SPEECH(ZCR_MAX_SPEECH),
        .HANGOVER_MS(HANGOVER_MS),
        .WINDOW_MS(WINDOW_MS)
    ) vad_inst (
        .clk(clk),
        .rst_n(rst_n),
        .audio_in(audio_in),
        .sample_valid(sample_valid),
        .speech_detected(speech_detected),
        .vad_raw(),
        .pre_trigger_pulse(pre_trigger_pulse),
        .recording_active(),
        .smoothed_energy(smoothed_energy),
        .noise_floor(noise_floor),
        .zero_cross_rate(zero_cross_rate)
    );

    // ─────────────────────────────────────────────────────────────────────
    // 2. Circular Buffer Instantiation (S2)
    // ─────────────────────────────────────────────────────────────────────
    circular_buffer #(
        .BUFFER_SIZE(BUFFER_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .PRE_TRIGGER_SAMPLES(PRE_TRIGGER_SAMPLES)
    ) circ_buf_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(audio_in),
        .sample_valid(sample_valid),
        .rd_en(rd_en),
        .pre_trig_rewind(pre_trig_rewind),
        .data_out(data_out),
        .data_valid(data_valid),
        .buffer_full()
    );

    // ─────────────────────────────────────────────────────────────────────
    // 3. FSM 1 Combinational Logic (CORA v4 Spec)
    // ─────────────────────────────────────────────────────────────────────
    always @(*) begin
        next_state      = state;
        pre_trig_rewind = 1'b0;
        rd_en           = 1'b0;
        speech_valid_r  = 1'b0;

        case (state)
            ST_IDLE: begin
                if (pre_trigger_pulse) next_state = ST_PRETRIG;
            end
            ST_PRETRIG: begin
                rd_en = 1'b1;
                if (pretrig_cnt == PRE_TRIGGER_SAMPLES - 1) next_state = ST_ACTIVE;
                else if (!speech_detected) next_state = ST_IDLE; // False trigger protection
            end
            ST_ACTIVE: begin
                rd_en = 1'b1;
                speech_valid_r = 1'b1;
                if (!speech_detected) next_state = ST_HANGOVER;
            end
            ST_HANGOVER: begin
                rd_en = 1'b1;
                speech_valid_r = 1'b1;
                if (speech_detected) next_state = ST_ACTIVE; // Re-trigger
                else if (hangover_ctr == 0) next_state = ST_IDLE;
            end
            default: next_state = ST_IDLE;
        endcase
    end

    // ─────────────────────────────────────────────────────────────────────
    // 4. FSM 1 Sequential Logic
    // ─────────────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            pretrig_cnt     <= 12'd0;
            hangover_ctr    <= 14'd0;
            pre_trig_rewind <= 1'b0;
        end else begin
            state <= next_state;

            // Rewind pulse exactly on IDLE->PRETRIG transition
            if (state == ST_IDLE && next_state == ST_PRETRIG)
                pre_trig_rewind <= 1'b1;
            else
                pre_trig_rewind <= 1'b0;

            // Pre-trigger counter
            if (state == ST_PRETRIG && rd_en)
                pretrig_cnt <= pretrig_cnt + 12'd1;
            else
                pretrig_cnt <= 12'd0;

            // Hangover counter
            if (state == ST_ACTIVE && next_state == ST_HANGOVER)
                hangover_ctr <= HANGOVER_CYCLES[13:0];
            else if (state == ST_HANGOVER)
                hangover_ctr <= hangover_ctr - 14'd1;
        end
    end
endmodule
