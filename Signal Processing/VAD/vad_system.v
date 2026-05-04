// ============================================================================
// 1. PMOD MIC INTERFACE: 12-bit unsigned PCM → 16-bit signed
// ============================================================================
module pmod_mic_interface_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire [11:0]   mic_data,           // Unsigned 12-bit PCM [0:4095]
    output reg signed [15:0] sample_out     // Signed 16-bit [-32768:32752]
);
    // Convert unsigned 12-bit to signed: subtract midpoint (2048)
    wire signed [11:0] mic_signed = $signed(mic_data) - 12'sd2048;
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            sample_out <= 16'd0;
        end else begin
            // Sign-extend to 16-bit, then shift left 4 (gain ×16 for headroom)
            sample_out <= {{4{mic_signed[11]}}, mic_signed} <<< 4;
        end
    end
endmodule

// ============================================================================
// 2. DC BLOCKER: 1st-order High-Pass Filter (HPF)
// Transfer function: y[n] = x[n] - x[n-1] + α·y[n-1], α = 0.995
// Removes DC offset critical for accurate ZCR calculation
// ============================================================================
module dc_blocker_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire signed [15:0] sample_in,
    output reg signed [15:0] sample_out
);
    // HPF coefficient: 0.995 ≈ 32600/32768 in Q15 fixed-point
    localparam signed [15:0] HPF_COEFF = 16'sd32600;
    
    reg signed [15:0] prev_input;
    reg signed [15:0] prev_output;
    reg [31:0] mult_result;
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            prev_input <= 16'd0;
            prev_output <= 16'd0;
            sample_out <= 16'd0;
        end else begin
            // Fixed-point multiply: prev_output * HPF_COEFF (Q15 × Q15 → Q30)
            mult_result <= $signed(prev_output) * $signed(HPF_COEFF);
            
            // y[n] = x[n] - x[n-1] + (α·y[n-1] >> 15)
            sample_out <= sample_in - prev_input + mult_result[30:15];
            
            // Update history
            prev_input <= sample_in;
            prev_output <= sample_out;
        end
    end
endmodule

// ============================================================================
// 3. CIRCULAR BUFFER: 160 samples (10ms @ 16 kHz) - Internal only
// Optional read interface for debugging/external access
// ============================================================================
module circular_buffer_160_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire signed [15:0] data_in,
    
    // Optional read interface
    input wire          read_en,
    input wire [7:0]    read_addr,
    output reg signed [15:0] read_data,
    
    output reg [7:0]    write_ptr,
    output wire         buffer_full
);
    // Internal buffer - NOT exposed as module port (Verilog compliance)
    reg signed [15:0] buffer [0:159];
    reg [7:0] sample_count;
    
    assign buffer_full = (sample_count >= 8'd160);
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            write_ptr <= 8'd0;
            sample_count <= 8'd0;
            read_data <= 16'd0;
        end else begin
            // Write new sample every cycle (16 kHz rate)
            buffer[write_ptr] <= data_in;
            write_ptr <= write_ptr + 8'd1;
            
            if (sample_count < 8'd160)
                sample_count <= sample_count + 8'd1;
            
            // Read interface (registered output)
            if (read_en)
                read_data <= buffer[read_addr];
        end
    end
endmodule

// ============================================================================
// 4. ENERGY ACCUMULATOR: sum(x²) over 160 samples, output >> 4
// Matches Python: energies = (sum(audio_int16**2)) >> 4
// ============================================================================
module energy_accumulator_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire signed [15:0] sample_in,
    output reg          done,               // Pulses high when frame complete
    output reg [31:0]   energy_out          // 32-bit energy value
);
    reg [39:0] energy_sum;  // 40-bit accumulator for sum of 160×(16-bit)²
    reg [7:0]  sample_cnt;
    reg        calculating;
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            energy_sum <= 40'd0;
            sample_cnt <= 8'd0;
            done <= 1'b0;
            calculating <= 1'b0;
            energy_out <= 32'd0;
        end else if (!calculating) begin
            // Start new frame accumulation
            calculating <= 1'b1;
            energy_sum <= 40'd0;
            sample_cnt <= 8'd0;
            done <= 1'b0;
        end else begin
            // Accumulate: energy += sample² (signed × signed → 32-bit)
            energy_sum <= energy_sum + $signed(sample_in) * $signed(sample_in);
            sample_cnt <= sample_cnt + 8'd1;
            
            // Frame complete after 160 samples (0 to 159)
            if (sample_cnt == 8'd159) begin
                energy_out <= energy_sum[39:4];  // >> 4 as in Python
                done <= 1'b1;
                calculating <= 1'b0;
            end else begin
                done <= 1'b0;
            end
        end
    end
endmodule

// ============================================================================
// 5. ZERO CROSSING COUNTER: Count sign changes per 160-sample frame
// Matches Python ZCR calculation (ignores zero samples)
// ============================================================================
module zero_crossing_counter_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire signed [15:0] sample_in,
    output reg          done,
    output reg [7:0]    zcr_count
);
    reg               prev_sign;      // Previous sample sign bit
    reg [7:0]         sample_cnt;
    reg [7:0]         crossing_cnt;
    reg               calculating;
    reg               first_sample;
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            crossing_cnt <= 8'd0;
            sample_cnt <= 8'd0;
            done <= 1'b0;
            calculating <= 1'b0;
            first_sample <= 1'b1;
            zcr_count <= 8'd0;
            prev_sign <= 1'b0;
        end else if (!calculating) begin
            // Start new frame
            calculating <= 1'b1;
            crossing_cnt <= 8'd0;
            sample_cnt <= 8'd0;
            first_sample <= 1'b1;
            done <= 1'b0;
        end else begin
            // Count zero crossings (sign changes), ignore zero-valued samples
            if (!first_sample && (sample_in != 16'd0) && (sample_in[15] != prev_sign))
                crossing_cnt <= crossing_cnt + 8'd1;
            else if (first_sample)
                first_sample <= 1'b0;
            
            prev_sign <= sample_in[15];
            sample_cnt <= sample_cnt + 8'd1;
            
            if (sample_cnt == 8'd159) begin
                zcr_count <= crossing_cnt;
                done <= 1'b1;
                calculating <= 1'b0;
            end else begin
                done <= 1'b0;
            end
        end
    end
endmodule

// ============================================================================
// 6. NOISE FLOOR TRACKER: Fast-Attack / Slow-Decay Envelope Follower
// Q16.16 fixed-point: alpha = 0.35 (attack) or 0.88 (decay)
// Matches Python: env[i] = α·env[i-1] + (1-α)·energy[i]
// ============================================================================
module noise_floor_tracker_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire          new_energy,     // Pulse when energy calculation done
    input wire [31:0]   energy_in,
    output reg [31:0]   envelope_out
);
    // Fixed-point parameters (Q16.16 format)
    localparam [16:0] FAST_ALPHA = 17'd22937;   // 0.35 × 65536
    localparam [16:0] SLOW_ALPHA = 17'd57672;   // 0.88 × 65536
    localparam [16:0] ONE_Q16 = 17'd65536;      // 1.0 in Q16.16
    
    reg [31:0] envelope_reg;
    reg [47:0] alpha_scaled;
    reg [63:0] temp_mult;
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            envelope_reg <= 32'd0;
            envelope_out <= 32'd0;
        end else if (new_energy) begin
            // Select alpha: fast attack if energy rising, slow decay otherwise
            if (energy_in > envelope_reg)
                alpha_scaled <= {32'd0, FAST_ALPHA};
            else
                alpha_scaled <= {32'd0, SLOW_ALPHA};
            
            // envelope = α·envelope + (1-α)·energy (Q16.16 arithmetic)
            temp_mult <= $signed(envelope_reg) * $signed(alpha_scaled[31:0]);
            envelope_reg <= temp_mult[47:16] + 
                           $signed(energy_in) * $signed(ONE_Q16 - alpha_scaled[16:0]);
            envelope_out <= envelope_reg;
        end
    end
endmodule

// ============================================================================
// 7. ADAPTIVE THRESHOLD CALCULATOR
// Calibration: First 200 frames (2 seconds) collect noise statistics
// Thresholds: off = 3×avg_noise, on = 8×avg_noise
// ============================================================================
module adaptive_threshold_calc_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire          frame_valid,    // Pulse every 10ms (160 samples)
    input wire [31:0]   energy_value,
    input wire          calibration_mode,
    output reg [31:0]   off_threshold,
    output reg [31:0]   on_threshold,
    output reg          thresholds_ready
);
    reg [39:0] energy_sum;
    reg [15:0] frame_count;
    localparam [15:0] CALIB_FRAMES = 16'd200;  // 2 seconds @ 10ms/frame
    
    // Default fallback thresholds (from Python reference)
    localparam [31:0] DEFAULT_OFF = 32'd702157211;
    localparam [31:0] DEFAULT_ON  = 32'd1558916091;
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            energy_sum <= 40'd0;
            frame_count <= 16'd0;
            off_threshold <= DEFAULT_OFF;
            on_threshold <= DEFAULT_ON;
            thresholds_ready <= 1'b0;
        end else if (calibration_mode && frame_valid) begin
            // Accumulate energy during calibration period
            energy_sum <= energy_sum + energy_value;
            frame_count <= frame_count + 16'd1;
            
            // After 200 frames, compute adaptive thresholds
            if (frame_count >= CALIB_FRAMES) begin
                off_threshold <= (energy_sum / CALIB_FRAMES) * 32'd3;
                on_threshold <= (energy_sum / CALIB_FRAMES) * 32'd8;
                thresholds_ready <= 1'b1;
            end
        end else if (frame_valid && !calibration_mode) begin
            // Keep thresholds ready after calibration completes
            thresholds_ready <= 1'b1;
        end
    end
endmodule

// ============================================================================
// 8. ENERGY COMPARATOR: Check if envelope in [off_thresh, on_thresh]
// ============================================================================
module energy_comparator_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire          energy_valid,
    input wire [31:0]   envelope_value,
    input wire [31:0]   off_thresh,
    input wire [31:0]   on_thresh,
    input wire          thresholds_ready,
    output reg          energy_pass
);
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst)
            energy_pass <= 1'b0;
        else if (energy_valid && thresholds_ready)
            energy_pass <= (envelope_value >= off_thresh) && 
                          (envelope_value <= on_thresh);
    end
endmodule

// ============================================================================
// 9. ZCR GATE: Check if ZCR in [15, 45] range
// ============================================================================
module zcr_gate_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire          zcr_valid,
    input wire [7:0]    zcr_value,
    output reg          zcr_pass
);
    localparam [7:0] ZCR_MIN = 8'd15;
    localparam [7:0] ZCR_MAX = 8'd45;
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst)
            zcr_pass <= 1'b0;
        else if (zcr_valid)
            zcr_pass <= (zcr_value >= ZCR_MIN) && (zcr_value <= ZCR_MAX);
    end
endmodule

// ============================================================================
// 10. VAD STATE MACHINE: IDLE → ACTIVE → HANGOVER
// Parameters: 200ms silence timeout, 50ms pre-trigger
// ============================================================================
module vad_state_machine_16khz (
    input wire          clk_16khz,
    input wire          rst,
    input wire          frame_trigger,  // energy_pass && zcr_pass
    output reg          speech_active,
    output reg          pretrigger_en,  // Pulse on IDLE→ACTIVE transition
    output reg          calibration_done
);
    localparam [1:0] STATE_CALIB = 2'b00;
    localparam [1:0] STATE_IDLE = 2'b01;
    localparam [1:0] STATE_ACTIVE = 2'b10;
    localparam [1:0] STATE_HANGOVER = 2'b11;
    
    reg [1:0] state;
    reg [7:0] silence_counter;
    reg [15:0] calib_timer;
    
    localparam [7:0] SILENCE_TIMEOUT = 8'd20;     // 200ms @ 10ms/frame
    localparam [15:0] CALIB_DURATION = 16'd200;   // 2 seconds calibration
    
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            state <= STATE_CALIB;
            silence_counter <= 8'd0;
            speech_active <= 1'b0;
            pretrigger_en <= 1'b0;
            calibration_done <= 1'b0;
            calib_timer <= 16'd0;
        end else begin
            pretrigger_en <= 1'b0;  // Default: no pre-trigger
            
            case (state)
                STATE_CALIB: begin
                    calib_timer <= calib_timer + 16'd1;
                    if (calib_timer >= CALIB_DURATION) begin
                        state <= STATE_IDLE;
                        calibration_done <= 1'b1;
                    end
                end
                
                STATE_IDLE: begin
                    if (frame_trigger) begin
                        state <= STATE_ACTIVE;
                        speech_active <= 1'b1;
                        pretrigger_en <= 1'b1;  // Enable pre-trigger capture
                        silence_counter <= 8'd0;
                    end
                end
                
                STATE_ACTIVE: begin
                    speech_active <= 1'b1;
                    if (frame_trigger)
                        silence_counter <= 8'd0;  // Reset timeout on trigger
                    else begin
                        silence_counter <= silence_counter + 8'd1;
                        if (silence_counter >= SILENCE_TIMEOUT)
                            state <= STATE_HANGOVER;
                    end
                end
                
                STATE_HANGOVER: begin
                    if (frame_trigger) begin
                        state <= STATE_ACTIVE;
                        speech_active <= 1'b1;
                        silence_counter <= 8'd0;
                    end else begin
                        silence_counter <= silence_counter + 8'd1;
                        if (silence_counter >= SILENCE_TIMEOUT) begin
                            state <= STATE_IDLE;
                            speech_active <= 1'b0;
                        end
                    end
                end
                
                default: begin
                    state <= STATE_IDLE;
                    speech_active <= 1'b0;
                end
            endcase
        end
    end
endmodule

// ============================================================================
// 11. TOP-LEVEL VAD MODULE
// ============================================================================
module vad_top_16khz_pure (
    input wire          clk_16khz,            // 16 kHz system clock
    input wire          rst,                  // Active-low reset
    
    // PMOD MIC Input (12-bit PCM @ 16 kHz)
    input wire [11:0]   mic_data,
    
    // Optional: Circular buffer read interface (debug/external use)
    input wire          buf_read_en,
    input wire [7:0]    buf_read_addr,
    output wire signed [15:0] buf_read_data,
    
    // VAD Outputs
    output reg          vad_output,           // Speech detected (updated every 10ms)
    output wire         frame_valid,          // Pulse every 10ms (160 samples)
    output wire [31:0]  energy_val,
    output wire [7:0]   zcr_val,
    output wire         calibration_active,
    output wire         thresholds_ready
);
    // Internal wires
    wire signed [15:0]  sample_16bit;
    wire signed [15:0]  dc_removed;
    wire                buffer_full;
    wire                energy_done;
    wire                zcr_done;
    reg                 new_frame;
    wire                energy_pass;
    wire                zcr_pass;
    wire                frame_trigger;
    wire                speech_active;
    wire                pretrigger_en;
    wire [31:0]         off_thresh;
    wire [31:0]         on_thresh;
    wire [31:0]         envelope_value;
    wire [7:0]          zcr_count;
    wire                calib_done;
    
    reg [7:0]           sample_counter;
    
    // ========================================================================
    // Signal Chain: MIC → Format → DC Removal → Buffer → Analysis → VAD
    // ========================================================================
    
    // 1. PMOD MIC: 12-bit unsigned → 16-bit signed
    pmod_mic_interface_16khz u_mic_if (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .mic_data(mic_data),
        .sample_out(sample_16bit)
    );
    
    // 2. DC Offset Removal (HPF)
    dc_blocker_16khz u_dc_blocker (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .sample_in(sample_16bit),
        .sample_out(dc_removed)
    );
    
    // 3. Circular Buffer (160 samples internal)
    circular_buffer_160_16khz u_circular_buffer (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .data_in(dc_removed),
        .read_en(buf_read_en),
        .read_addr(buf_read_addr),
        .read_data(buf_read_data),
        .write_ptr(),
        .buffer_full(buffer_full)
    );
    
    // 4. Frame Generation: Count 160 samples = 10ms frame
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst) begin
            sample_counter <= 8'd0;
            new_frame <= 1'b0;
        end else begin
            new_frame <= 1'b0;
            if (sample_counter == 8'd159) begin
                sample_counter <= 8'd0;
                new_frame <= 1'b1;  // Frame complete!
            end else begin
                sample_counter <= sample_counter + 8'd1;
            end
        end
    end
    assign frame_valid = new_frame;
    
    // 5. Energy Accumulator (continuous processing, output every frame)
    energy_accumulator_16khz u_energy (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .sample_in(dc_removed),
        .done(energy_done),
        .energy_out(energy_val)
    );
    
    // 6. Zero Crossing Counter
    zero_crossing_counter_16khz u_zcr (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .sample_in(dc_removed),
        .done(zcr_done),
        .zcr_count(zcr_val)
    );
    
    // 7. Noise Floor Tracker (updates on new energy)
    noise_floor_tracker_16khz u_noise (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .new_energy(energy_done),
        .energy_in(energy_val),
        .envelope_out(envelope_value)
    );
    
    // 8. Adaptive Threshold Calculator
    adaptive_threshold_calc_16khz u_thresh_calc (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .frame_valid(new_frame),
        .energy_value(energy_val),
        .calibration_mode(!calib_done),
        .off_threshold(off_thresh),
        .on_threshold(on_thresh),
        .thresholds_ready(thresholds_ready)
    );
    assign calibration_active = !calib_done;
    
    // 9. Energy Comparator
    energy_comparator_16khz u_energy_comp (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .energy_valid(energy_done),
        .envelope_value(envelope_value),
        .off_thresh(off_thresh),
        .on_thresh(on_thresh),
        .thresholds_ready(thresholds_ready),
        .energy_pass(energy_pass)
    );
    
    // 10. ZCR Gate
    zcr_gate_16khz u_zcr_gate (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .zcr_valid(zcr_done),
        .zcr_value(zcr_val),
        .zcr_pass(zcr_pass)
    );
    
    // Trigger = Energy OK AND ZCR OK
    assign frame_trigger = energy_pass && zcr_pass;
    
    // 11. VAD State Machine
    vad_state_machine_16khz u_vad_sm (
        .clk_16khz(clk_16khz),
        .rst(rst),
        .frame_trigger(frame_trigger),
        .speech_active(speech_active),
        .pretrigger_en(pretrigger_en),
        .calibration_done(calib_done)
    );
    
    // 12. VAD Output (updated every frame)
    always @(posedge clk_16khz or negedge rst) begin
        if (!rst)
            vad_output <= 1'b0;
        else if (new_frame)
            vad_output <= speech_active;
    end

endmodule
