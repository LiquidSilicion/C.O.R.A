module vad #(
    parameter SAMPLE_RATE = 16000,
    parameter CLK_FREQ = 100000000,
    parameter THRESHOLD_ON = 32'd2000000,
    parameter THRESHOLD_OFF = 32'd1000000,
    parameter THRESHOLD_ADAPT_RATE = 4,
    parameter ZCR_MIN_SPEECH = 15,
    parameter ZCR_MAX_SPEECH = 45,
    parameter HANGOVER_MS = 300,
    parameter PRE_TRIGGER_MS = 200,
    parameter WINDOW_MS = 10,
    parameter SAMPLES_PER_WINDOW = SAMPLE_RATE * WINDOW_MS / 1000,
    parameter HANGOVER_SAMPLES = SAMPLE_RATE * HANGOVER_MS / 1000,
    parameter PRE_TRIGGER_SAMPLES = SAMPLE_RATE * PRE_TRIGGER_MS / 1000,
    parameter ALPHA_NOISE = 16'd63550,
    parameter ALPHA_ENERGY = 16'd58054
)(
    input wire clk,
    input wire rst_n,
    input wire [15:0] audio_in,
    input wire sample_valid,
    output reg speech_detected,
    output reg vad_raw,
    output reg recording_active,
    output reg pre_trigger_active,
    output reg [31:0] smoothed_energy,
    output reg [31:0] noise_floor,
    output reg [15:0] zero_cross_rate
);

    reg [31:0] energy_accum;
    reg [15:0] sample_count;
    reg [31:0] window_energy;
    reg [31:0] energy_smoothed;
    reg [31:0] energy_history [0:3];
    reg [1:0] history_ptr;
    reg [31:0] noise_floor_reg;
    reg [31:0] min_energy_window;
    reg [15:0] zcr_count;
    reg last_sample_sign;
    reg [15:0] zcr_smoothed;
    reg energy_vad;
    reg zcr_vad;
    reg [15:0] hangover_counter;
    reg [15:0] pre_trigger_counter;
    
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            energy_accum <= 32'd0;
            sample_count <= 16'd0;
            window_energy <= 32'd0;
            smoothed_energy <= 32'd0;
            history_ptr <= 2'd0;
            for (i = 0; i < 4; i=i+1) begin
                energy_history[i] <= 32'd0;
            end
        end else if (sample_valid) begin
            energy_accum <= energy_accum + ($signed(audio_in) * $signed(audio_in));
            sample_count <= sample_count + 1;
            
            if (sample_count == SAMPLES_PER_WINDOW - 1) begin
                window_energy <= energy_accum;
                energy_history[history_ptr] <= energy_accum;
                history_ptr <= history_ptr + 1;
                energy_smoothed <= (ALPHA_ENERGY * energy_smoothed >> 16) + 
                                   ((65535 - ALPHA_ENERGY) * energy_accum >> 16);
                energy_accum <= 32'd0;
                sample_count <= 16'd0;
                
                if (!vad_raw) begin
                    if (energy_accum < noise_floor_reg) begin
                        noise_floor_reg <= energy_accum;
                    end else begin
                        noise_floor_reg <= noise_floor_reg + 
                                          ((energy_accum - noise_floor_reg) >> THRESHOLD_ADAPT_RATE);
                    end
                end
            end
        end
    end
    
    always @(posedge clk) begin
        smoothed_energy <= energy_smoothed;
        noise_floor <= noise_floor_reg;
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zcr_count <= 16'd0;
            last_sample_sign <= 1'b0;
            zcr_smoothed <= 16'd0;
        end else if (sample_valid) begin
            if ((audio_in[15] ^ last_sample_sign) && (audio_in != 16'd0)) begin
                zcr_count <= zcr_count + 1;
            end
            last_sample_sign <= audio_in[15];
            
            if (sample_count == SAMPLES_PER_WINDOW - 1) begin
                zcr_smoothed <= (zcr_smoothed * 3 + zcr_count) >> 2;
                zero_cross_rate <= zcr_count;
                zcr_count <= 16'd0;
            end
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            energy_vad <= 1'b0;
        end else begin
            if (energy_smoothed > (noise_floor_reg * 4)) begin
                energy_vad <= 1'b1;
            end else if (energy_smoothed < (noise_floor_reg * 2)) begin
                energy_vad <= 1'b0;
            end
        end
    end
    
    always @(posedge clk) begin
        zcr_vad <= (zcr_smoothed > ZCR_MIN_SPEECH) && (zcr_smoothed < ZCR_MAX_SPEECH);
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vad_raw <= 1'b0;
        end else begin
            vad_raw <= energy_vad && zcr_vad;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            speech_detected <= 1'b0;
            hangover_counter <= 16'd0;
        end else begin
            if (vad_raw) begin
                speech_detected <= 1'b1;
                hangover_counter <= HANGOVER_SAMPLES;
            end else if (hangover_counter > 0) begin
                speech_detected <= 1'b1;
                hangover_counter <= hangover_counter - 1;
            end else begin
                speech_detected <= 1'b0;
            end
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pre_trigger_active <= 1'b0;
            pre_trigger_counter <= 16'd0;
            recording_active <= 1'b0;
        end else begin
            if (vad_raw && !pre_trigger_active && !speech_detected) begin
                pre_trigger_active <= 1'b1;
                pre_trigger_counter <= PRE_TRIGGER_SAMPLES;
            end else if (pre_trigger_active) begin
                if (pre_trigger_counter > 0) begin
                    pre_trigger_counter <= pre_trigger_counter - 1;
                end else begin
                    pre_trigger_active <= 1'b0;
                end
            end
            recording_active <= pre_trigger_active || speech_detected;
        end
    end

endmodule
