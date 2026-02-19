module vad_energy_detector #(
    parameter SAMPLE_RATE = 16000,
    parameter THRESHOLD = 32'd1000000,
    parameter HANGOVER_MS = 300,
    parameter BUFFER_SIZE_MS = 1500
)(
    input wire clk,
    input wire rst_n,
    input wire [15:0] audio_in,
    input wire sample_valid,
    
    output reg speech_detected,
    output reg [31:0] smoothed_energy,
    output reg recording_active
);

    localparam CLK_FREQ = 100000000;
    localparam SAMPLES_PER_10MS = SAMPLE_RATE / 100;
    localparam HANGOVER_MAX = (SAMPLE_RATE * HANGOVER_MS / 1000) - 1;
    localparam ALPHA = 16'd62259;

    reg [31:0] energy_accum;
    reg [15:0] sample_count;
    reg [31:0] short_term_energy;
    reg [31:0] energy_history [0:9];
    reg [3:0] history_ptr;
    
    reg [31:0] alpha_fixed;
    reg [31:0] one_minus_alpha;
    
    reg [15:0] hangover_counter;
    reg vad_raw;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            energy_accum <= 0;
            sample_count <= 0;
            short_term_energy <= 0;
            smoothed_energy <= 0;
            vad_raw <= 0;
            speech_detected <= 0;
            hangover_counter <= 0;
            recording_active <= 0;
            history_ptr <= 0;
            
            for (i = 0; i < 10; i = i + 1) begin
                energy_history[i] <= 0;
            end
            
            alpha_fixed <= ALPHA;
            one_minus_alpha <= 65535 - ALPHA;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end else if (sample_valid) begin
            energy_accum <= energy_accum + (audio_in * audio_in);
            sample_count <= sample_count + 1;
            
            if (sample_count >= SAMPLES_PER_10MS - 1) begin
                short_term_energy <= energy_accum;
                energy_history[history_ptr] <= energy_accum;
                history_ptr <= (history_ptr == 9) ? 0 : history_ptr + 1;
                energy_accum <= 0;
                sample_count <= 0;
                smoothed_energy <= (alpha_fixed * smoothed_energy >> 16) + 
                                   (one_minus_alpha * short_term_energy >> 16);
            end
        end
    end

    always @(*) begin
        if (smoothed_energy > THRESHOLD) begin
            vad_raw = 1'b1;
        end else if (smoothed_energy < (THRESHOLD >> 1)) begin
            vad_raw = 1'b0;
        end else begin
            vad_raw = vad_raw;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            speech_detected <= 0;
            hangover_counter <= 0;
        end else begin
            recording_active <= speech_detected;
            
            if (vad_raw) begin
                speech_detected <= 1'b1;
                hangover_counter <= HANGOVER_MAX;
            end else if (hangover_counter > 0) begin
                speech_detected <= 1'b1;
                hangover_counter <= hangover_counter - 1;
            end else begin
                speech_detected <= 1'b0;
            end
        end
    end

    reg [15:0] zero_cross_count;
    reg [15:0] zcr_window [0:15];
    reg [3:0] zcr_ptr;
    reg last_sample_sign;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zero_cross_count <= 0;
            last_sample_sign <= 0;
        end else if (sample_valid) begin
            if ((audio_in[15] ^ last_sample_sign) && (audio_in != 0)) begin
                zero_cross_count <= zero_cross_count + 1;
            end
            last_sample_sign <= audio_in[15];
            
            if (sample_count >= SAMPLES_PER_10MS - 1) begin
                zcr_window[zcr_ptr] <= zero_cross_count;
                zcr_ptr <= (zcr_ptr == 15) ? 0 : zcr_ptr + 1;
                zero_cross_count <= 0;
            end
        end
    end

    reg [31:0] noise_floor;
    reg [31:0] min_energy;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            noise_floor <= 32'd10000;
            min_energy <= 32'hFFFFFFFF;
        end else begin
            if (short_term_energy < min_energy && sample_count == 0) begin
                min_energy <= short_term_energy;
            end
        end
    end

endmodule
