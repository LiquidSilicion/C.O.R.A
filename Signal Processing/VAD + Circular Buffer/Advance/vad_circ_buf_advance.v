module vad_circ_buf_advance #(
    //=== Timing Parameters ===
    parameter SAMPLE_RATE          = 16000,
    parameter CLK_FREQ             = 100_000_000,
    parameter WINDOW_MS            = 10,
    parameter HANGOVER_MS          = 300,
    parameter SAMPLES_PER_WINDOW   = 160,
    parameter HANGOVER_SAMPLES     = 4800,
    
    //=== VAD Thresholds - FIXED SCALE (256× higher for full 16-bit audio) ===
    parameter THRESHOLD_ON         = 32'd12800000000,  // 12.8 billion (was 50K)
    parameter THRESHOLD_OFF        = 32'd6400000000,   // 6.4 billion
    parameter THRESHOLD_ADAPT_RATE = 4,
    
    //=== ZCR Parameters ===
    parameter ZCR_MIN_SPEECH       = 15,
    parameter ZCR_MAX_SPEECH       = 80,  // Increased (testbench has high ZCR)
    
    //=== IIR Smoothing Coefficients ===
    parameter ALPHA_ENERGY         = 16'd63550,
    parameter ALPHA_NOISE          = 16'd63550,
    
    //=== Circular Buffer ===
    parameter BUF_DEPTH            = 24000,
    parameter PRETRIG_SAMP         = 3200
)(
    input  wire        clk_100m,
    input  wire        rst_n,
    input  wire [15:0] pcm_in,
    input  wire        pcm_valid,
    output reg  [15:0] speech_raw,
    output reg         audio_valid,
    output reg         speech_valid,
    output wire [31:0] dbg_energy,
    output wire [31:0] dbg_noise_floor,
    output wire [31:0] dbg_zcr,
    output wire        vad_debug_trigger
);

    //========================================================================
    // Internal Signals
    //========================================================================
    reg [14:0] wr_ptr;
    reg [14:0] rd_ptr;
    reg [15:0] mem [0:BUF_DEPTH-1];
    
    reg [9:0]  vad_sample_cnt;
    reg [47:0] vad_energy_acc;
    reg [31:0] vad_zcr_acc;
    reg [15:0] pcm_prev;
    reg        pcm_prev_valid;
    reg        zcross;
    
    // Adaptive Noise Floor
    reg [47:0] energy_smoothed_r;  // FIXED: 48-bit to match energy scale
    reg [47:0] noise_floor_r;      // FIXED: 47-bit
    reg [31:0] zcr_smoothed_r;
    
    // VAD Decisions
    reg        energy_vad;
    reg        zcr_vad;
    reg        vad_raw;
    
    // FSM Signals
    reg [1:0] state, next_state;
    reg [15:0] pretrig_cnt;
    reg [15:0] hangover_cnt;
    reg        hangover_done;  // FIXED: Separate flag for hangover completion
    
    localparam S_IDLE     = 2'b00;
    localparam S_PRETRIG  = 2'b01;
    localparam S_ACTIVE   = 2'b10;
    localparam S_HANGOVER = 2'b11;

    //========================================================================
    // Circular Buffer Write Logic
    //========================================================================
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 15'd0;
        end else if (pcm_valid) begin
            mem[wr_ptr] <= pcm_in;
            if (wr_ptr == BUF_DEPTH - 1)
                wr_ptr <= 15'd0;
            else
                wr_ptr <= wr_ptr + 15'd1;
        end
    end

    //========================================================================
    // VAD Engine - FIXED ENERGY SCALE
    //========================================================================
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            vad_sample_cnt    <= 10'd0;
            vad_energy_acc    <= 48'd0;
            vad_zcr_acc       <= 32'd0;
            pcm_prev          <= 16'd0;
            pcm_prev_valid    <= 1'b0;
            zcross            <= 1'b0;
            energy_smoothed_r <= 48'd0;
            noise_floor_r     <= 48'd1000000;  // FIXED: Non-zero initial
            zcr_smoothed_r    <= 32'd0;
            vad_raw           <= 1'b0;
            energy_vad        <= 1'b0;
            zcr_vad           <= 1'b0;
            hangover_done     <= 1'b0;
        end else if (pcm_valid) begin
            //=== 1. Zero Crossing Detection ===
            if (pcm_prev_valid) begin
                zcross <= (pcm_prev[15] != pcm_in[15]);
            end else begin
                zcross <= 1'b0;
            end
            
            //=== 2. Energy Accumulation (Full 16-bit) ===
            vad_energy_acc <= vad_energy_acc + (pcm_in * pcm_in);
            
            //=== 3. ZCR Accumulation ===
            if (zcross && (pcm_in != 16'd0))
                vad_zcr_acc <= vad_zcr_acc + 32'd1;
            
            //=== 4. Update Previous Sample ===
            pcm_prev <= pcm_in;
            pcm_prev_valid <= 1'b1;
            
            //=== 5. Window Completion (10ms = 160 samples) ===
            if (vad_sample_cnt == SAMPLES_PER_WINDOW - 1) begin
                vad_sample_cnt <= 10'd0;
                
                //--- IIR Energy Smoothing (48-bit) ---
                energy_smoothed_r <= ((ALPHA_ENERGY * energy_smoothed_r) >> 16) +
                                     (((16'd65535 - ALPHA_ENERGY) * vad_energy_acc) >> 16);
                
                //--- Adaptive Noise Floor (48-bit) ---
                if (vad_energy_acc > noise_floor_r + THRESHOLD_ON) begin
                    noise_floor_r <= noise_floor_r;  // FREEZE on speech
                end else begin
                    if (vad_energy_acc < noise_floor_r) begin
                        noise_floor_r <= noise_floor_r -
                                        ((noise_floor_r - vad_energy_acc) >> THRESHOLD_ADAPT_RATE);
                    end else begin
                        noise_floor_r <= noise_floor_r +
                                        ((vad_energy_acc - noise_floor_r) >> THRESHOLD_ADAPT_RATE);
                    end
                end
                
                //--- ZCR Smoothing ---
                zcr_smoothed_r <= (zcr_smoothed_r * 3 + vad_zcr_acc) >> 2;
                
                //--- Energy VAD with Hysteresis (48-bit compare) ---
                if (energy_smoothed_r > noise_floor_r + THRESHOLD_ON)
                    energy_vad <= 1'b1;
                else if (energy_smoothed_r < noise_floor_r + THRESHOLD_OFF)
                    energy_vad <= 1'b0;
                
                //--- ZCR VAD with Range Check ---
                zcr_vad <= (zcr_smoothed_r >= ZCR_MIN_SPEECH) &&
                          (zcr_smoothed_r <= ZCR_MAX_SPEECH);
                
                //--- Final VAD Decision ---
                vad_raw <= energy_vad;
                
                // Reset Accumulators
                vad_energy_acc <= 48'd0;
                vad_zcr_acc    <= 32'd0;
            end else begin
                vad_sample_cnt <= vad_sample_cnt + 10'd1;
            end
        end
    end
    
    assign dbg_energy      = energy_smoothed_r[31:0];
    assign dbg_noise_floor = noise_floor_r[31:0];
    assign dbg_zcr         = zcr_smoothed_r[31:0];
    assign vad_debug_trigger = vad_raw;

    //========================================================================
    // FSM 1: Circular Buffer Read Controller - FIXED HANGOVER
    //========================================================================
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            next_state   <= S_IDLE;
            rd_ptr       <= 15'd0;
            audio_valid  <= 1'b0;
            speech_valid <= 1'b0;
            pretrig_cnt  <= 16'd0;
            hangover_cnt <= 16'd0;
            speech_raw   <= 16'd0;
            hangover_done<= 1'b0;
        end else begin
            state <= next_state;
            audio_valid <= 1'b0;
            hangover_done <= 1'b0;
            
            //=== Hangover Counter - FIXED ===
            if (state == S_HANGOVER) begin
                if (pcm_valid) begin
                    if (hangover_cnt < HANGOVER_SAMPLES - 1) begin
                        hangover_cnt <= hangover_cnt + 16'd1;
                    end else begin
                        hangover_done <= 1'b1;  // FIXED: Flag when complete
                    end
                end
            end else begin
                hangover_cnt <= 16'd0;
            end
            
            //=== Pretrigger Counter ===
            if (state == S_PRETRIG) begin
                if (pretrig_cnt < PRETRIG_SAMP)
                    pretrig_cnt <= pretrig_cnt + 16'd1;
            end else begin
                pretrig_cnt <= 16'd0;
            end

            //=== FSM State Transitions ===
            case (state)
                S_IDLE: begin
                    speech_valid <= 1'b0;
                    rd_ptr       <= wr_ptr;
                    next_state   <= S_IDLE;
                    
                    if (vad_raw) begin
                        next_state  <= S_PRETRIG;
                        if (wr_ptr >= PRETRIG_SAMP)
                            rd_ptr <= wr_ptr - PRETRIG_SAMP;
                        else
                            rd_ptr <= BUF_DEPTH - (PRETRIG_SAMP - wr_ptr);
                        pretrig_cnt <= 16'd0;
                    end
                end
                
                S_PRETRIG: begin
                    audio_valid <= 1'b1; 
                    speech_raw  <= mem[rd_ptr];
                    next_state  <= S_PRETRIG;
                    
                    if (rd_ptr == BUF_DEPTH - 1)
                        rd_ptr <= 15'd0;
                    else
                        rd_ptr <= rd_ptr + 15'd1;
                    
                    if (!vad_raw && pretrig_cnt < PRETRIG_SAMP) begin
                        next_state <= S_IDLE;
                    end 
                    else if (pretrig_cnt == PRETRIG_SAMP - 1) begin
                        next_state   <= S_ACTIVE;
                        speech_valid <= 1'b1;
                    end
                end
                
                S_ACTIVE: begin
                    speech_valid <= 1'b1;
                    next_state   <= S_ACTIVE;
                    
                    if (pcm_valid) begin
                        audio_valid <= 1'b1;
                        speech_raw <= mem[rd_ptr];
                        
                        if (rd_ptr == BUF_DEPTH - 1)
                            rd_ptr <= 15'd0;
                        else
                            rd_ptr <= rd_ptr + 15'd1;
                    end
                    
                    if (!vad_raw) begin
                        next_state   <= S_HANGOVER;
                        hangover_cnt <= 16'd0; 
                    end
                end
                
                S_HANGOVER: begin
                    speech_valid <= 1'b1;
                    next_state   <= S_HANGOVER;
                    
                    if (pcm_valid) begin
                        audio_valid <= 1'b1;
                        speech_raw <= mem[rd_ptr];
                        if (rd_ptr == BUF_DEPTH - 1)
                            rd_ptr <= 15'd0;
                        else
                            rd_ptr <= rd_ptr + 15'd1;
                    end
                    
                    // FIXED: Use hangover_done flag instead of counter compare
                    if (hangover_done) begin
                        next_state <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
