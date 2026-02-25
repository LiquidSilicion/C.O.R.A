module vad #(
    parameter SAMPLE_RATE = 16000,
    parameter CLK_FREQ = 100_000_000,
    parameter THRESHOLD_ON = 32'd2000000,
    parameter THRESHOLD_OFF = 32'd1000000,
    parameter THRESHOLD_ADAPT_RATE = 4,
    parameter ZCR_MIN_SPEECH = 15,
    parameter ZCR_MAX_SPEECH = 45,
    parameter HANGOVER_MS = 300,
    parameter WINDOW_MS = 10,
    parameter SAMPLES_PER_WINDOW = SAMPLE_RATE * WINDOW_MS / 1000,
    parameter HANGOVER_SAMPLES = SAMPLE_RATE * HANGOVER_MS / 1000,
    parameter ALPHA_NOISE = 16'd63550,
    parameter ALPHA_ENERGY = 16'd58054
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [15:0] audio_in,
    input  wire sample_valid,
    output reg speech_detected,
    output reg vad_raw,
    output reg pre_trigger_pulse,
    output reg recording_active,
    output reg [31:0] smoothed_energy,
    output reg [31:0] noise_floor,
    output reg [15:0] zero_cross_rate
);

    reg [31:0] energy_accum;
    reg [15:0] sample_count;
    reg [31:0] energy_smoothed_r;
    reg [31:0] noise_floor_r;
    reg [7:0]  zcr_count;
    reg last_sign;
    reg [7:0]  zcr_smoothed_r;
    reg energy_vad;
    reg zcr_vad;
    reg [13:0] hangover_ctr;
    reg prev_speech_detected;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            energy_accum     <= 32'd0;
            sample_count     <= 16'd0;
            energy_smoothed_r<= 32'd0;
            noise_floor_r    <= THRESHOLD_OFF;
        end else if (sample_valid) begin
            energy_accum <= energy_accum +
                            ({16'd0, $unsigned(audio_in)} *
                             {16'd0, $unsigned(audio_in)});
            sample_count <= sample_count + 1;

            if (sample_count == SAMPLES_PER_WINDOW - 1) begin
                energy_smoothed_r <= (ALPHA_ENERGY  * energy_smoothed_r  >> 16) +
                                     ((16'd65535 - ALPHA_ENERGY) * energy_accum >> 16);
                if (!vad_raw) begin
                    if (energy_accum < noise_floor_r)
                        noise_floor_r <= energy_accum;
                    else
                        noise_floor_r <= noise_floor_r +
                            ((energy_accum - noise_floor_r) >> THRESHOLD_ADAPT_RATE);
                end
                energy_accum <= 32'd0;
                sample_count <= 16'd0;
            end
        end
    end

    always @(posedge clk) begin
        smoothed_energy <= energy_smoothed_r;
        noise_floor     <= noise_floor_r;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zcr_count      <= 8'd0;
            last_sign      <= 1'b0;
            zcr_smoothed_r <= 8'd0;
            zero_cross_rate<= 16'd0;
        end else if (sample_valid) begin
            if ((audio_in[15] ^ last_sign) && (audio_in != 16'd0))
                zcr_count <= zcr_count + 1;
            last_sign <= audio_in[15];
            if (sample_count == SAMPLES_PER_WINDOW - 1) begin
                zcr_smoothed_r  <= (zcr_smoothed_r * 3 + zcr_count) >> 2;
                zero_cross_rate <= {8'd0, zcr_count};
                zcr_count       <= 8'd0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            energy_vad <= 1'b0;
        end else begin
            if      (energy_smoothed_r > (noise_floor_r << 2))
                energy_vad <= 1'b1;
            else if (energy_smoothed_r < (noise_floor_r << 1))
                energy_vad <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zcr_vad <= 1'b0;
        end else begin
            zcr_vad <= (zcr_smoothed_r >= ZCR_MIN_SPEECH) &&
                       (zcr_smoothed_r <= ZCR_MAX_SPEECH);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            vad_raw <= 1'b0;
        else
            vad_raw <= energy_vad && zcr_vad;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            speech_detected <= 1'b0;
            hangover_ctr    <= 14'd0;
        end else begin
            if (vad_raw) begin
                speech_detected <= 1'b1;
                hangover_ctr    <= HANGOVER_SAMPLES[13:0];
            end else if (hangover_ctr > 14'd0) begin
                speech_detected <= 1'b1;
                hangover_ctr    <= hangover_ctr - 1;
            end else begin
                speech_detected <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_speech_detected <= 1'b0;
            pre_trigger_pulse    <= 1'b0;
            recording_active     <= 1'b0;
        end else begin
            prev_speech_detected <= speech_detected;
            pre_trigger_pulse <= speech_detected && !prev_speech_detected;
            recording_active  <= speech_detected;
        end
    end

endmodule
