module cora_vad_circ_buf (
    input  wire        clk_100m,
    input  wire        rst_n,
    input  wire [15:0] pcm_in,
    input  wire        pcm_valid,
    output reg  [15:0] speech_raw,
    output reg         audio_valid,
    output reg         speech_valid,
    output wire [31:0] dbg_energy,
    output wire [31:0] dbg_zcr
);

    //========================================================================
    // Parameters
    //========================================================================
    localparam BUF_DEPTH    = 24000;
    localparam BUF_ADDR_W   = 15;
    localparam VAD_WIN_SAMP = 160;
    localparam HANGOVER_SAMP= 4800;
    localparam PRETRIG_SAMP = 3200;
    localparam ENERGY_THRESH = 48'd1000000000;
    localparam ZCR_THRESH    = 16'd40;

    //========================================================================
    // Internal Signals - FIXED WIDTHS
    //========================================================================
    reg [BUF_ADDR_W-1:0] wr_ptr;
    reg [BUF_ADDR_W-1:0] rd_ptr;
    reg [15:0]           mem [0:BUF_DEPTH-1];
    
    reg [9:0]  vad_sample_cnt;
    reg [47:0] vad_energy_acc;
    reg [31:0] vad_zcr_acc;  // FIXED: Was 16-bit, now 32-bit to match dbg_zcr
    reg [15:0] pcm_prev;
    reg        vad_raw_trigger;
    reg        zcross;
    reg        pcm_prev_valid;
    
    reg [1:0] state, next_state;
    reg [15:0] pretrig_cnt;
    reg [15:0] hangover_cnt;
    
    localparam S_IDLE     = 2'b00;
    localparam S_PRETRIG  = 2'b01;
    localparam S_ACTIVE   = 2'b10;
    localparam S_HANGOVER = 2'b11;

    //========================================================================
    // Circular Buffer Write Logic
    //========================================================================
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (pcm_valid) begin
            mem[wr_ptr] <= pcm_in;
            if (wr_ptr == BUF_DEPTH - 1)
                wr_ptr <= 0;
            else
                wr_ptr <= wr_ptr + 1;
        end
    end

    //========================================================================
    // VAD Engine - FIXED ZCR WIDTH & INIT
    //========================================================================
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            vad_sample_cnt   <= 10'd0;
            vad_energy_acc   <= 48'd0;
            vad_zcr_acc      <= 32'd0;  // FIXED: Proper width init
            pcm_prev         <= 16'd0;
            pcm_prev_valid   <= 1'b0;
            vad_raw_trigger  <= 1'b0;
            zcross           <= 1'b0;
        end else if (pcm_valid) begin
            // Zero Crossing Detection
            if (pcm_prev_valid) begin
                zcross <= (pcm_prev[15] != pcm_in[15]);
            end else begin
                zcross <= 1'b0;
            end
            
            // Energy Calculation
            vad_energy_acc <= vad_energy_acc + (pcm_in * pcm_in);
            
            // Accumulate ZCR
            if (zcross) 
                vad_zcr_acc <= vad_zcr_acc + 32'd1;
            
            // Update Previous Sample
            pcm_prev <= pcm_in;
            pcm_prev_valid <= 1'b1;
            
            // Window Completion (10ms = 160 samples)
            if (vad_sample_cnt == VAD_WIN_SAMP - 1) begin
                vad_sample_cnt <= 10'd0;
                
                if (vad_energy_acc > ENERGY_THRESH || vad_zcr_acc > ZCR_THRESH) begin
                    vad_raw_trigger <= 1'b1;
                end else begin
                    vad_raw_trigger <= 1'b0;
                end
                
                vad_energy_acc <= 48'd0;
                vad_zcr_acc    <= 32'd0;
            end else begin
                vad_sample_cnt <= vad_sample_cnt + 10'd1;
            end
        end
    end
    
    // FIXED: Proper width assignment
    assign dbg_energy = vad_energy_acc[31:0];
    assign dbg_zcr    = vad_zcr_acc[31:0];   // Now matches 32-bit reg

    //========================================================================
    // FSM 1: Circular Buffer Read Controller
    //========================================================================
    always @(posedge clk_100m or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            next_state   <= S_IDLE;
            rd_ptr       <= 0;
            audio_valid  <= 0;
            speech_valid <= 0;
            pretrig_cnt  <= 0;
            hangover_cnt <= 0;
            speech_raw   <= 0;
        end else begin
            state <= next_state;
            audio_valid <= 0;
            
            // Hangover counter
            if (pcm_valid && (state == S_ACTIVE || state == S_HANGOVER)) begin
                if (hangover_cnt < HANGOVER_SAMP)
                    hangover_cnt <= hangover_cnt + 1;
            end else begin
                hangover_cnt <= 0;
            end
            
            // Pretrigger counter
            if (state == S_PRETRIG) begin
                if (pretrig_cnt < PRETRIG_SAMP)
                    pretrig_cnt <= pretrig_cnt + 1;
            end else begin
                pretrig_cnt <= 0;
            end

            case (state)
                S_IDLE: begin
                    speech_valid <= 0;
                    rd_ptr       <= wr_ptr;
                    next_state   <= S_IDLE;
                    
                    if (vad_raw_trigger) begin
                        next_state  <= S_PRETRIG;
                        if (wr_ptr >= PRETRIG_SAMP)
                            rd_ptr <= wr_ptr - PRETRIG_SAMP;
                        else
                            rd_ptr <= BUF_DEPTH - (PRETRIG_SAMP - wr_ptr);
                        pretrig_cnt <= 0;
                    end
                end
                
                S_PRETRIG: begin
                    audio_valid <= 1; 
                    speech_raw  <= mem[rd_ptr];
                    next_state  <= S_PRETRIG;  // Default stay in PRETRIG
                    
                    if (rd_ptr == BUF_DEPTH - 1)
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                    
                    // False trigger protection: VAD drops BEFORE completing 3200
                    if (!vad_raw_trigger && pretrig_cnt < PRETRIG_SAMP) begin
                        next_state <= S_IDLE;
                    end 
                    // Complete pre-trigger burst
                    else if (pretrig_cnt == PRETRIG_SAMP - 1) begin
                        next_state   <= S_ACTIVE;
                        speech_valid <= 1;
                    end
                end
                
                S_ACTIVE: begin
                    speech_valid <= 1;
                    next_state   <= S_ACTIVE;
                    
                    if (pcm_valid) begin
                        audio_valid <= 1;
                        speech_raw <= mem[rd_ptr];
                        
                        if (rd_ptr == BUF_DEPTH - 1)
                            rd_ptr <= 0;
                        else
                            rd_ptr <= rd_ptr + 1;
                    end
                    
                    if (!vad_raw_trigger) begin
                        next_state   <= S_HANGOVER;
                        hangover_cnt <= 0; 
                    end
                end
                
                S_HANGOVER: begin
                    speech_valid <= 1;
                    next_state   <= S_HANGOVER;
                    
                    if (pcm_valid) begin
                        audio_valid <= 1;
                        speech_raw <= mem[rd_ptr];
                        if (rd_ptr == BUF_DEPTH - 1)
                            rd_ptr <= 0;
                        else
                            rd_ptr <= rd_ptr + 1;
                    end
                    
                    if (hangover_cnt >= HANGOVER_SAMP - 1) begin
                        next_state <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
