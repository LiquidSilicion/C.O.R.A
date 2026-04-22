module sp_pipeline(
    input  wire        clk,              // 100 MHz System Clock
    input  wire        rst_n,            // Active-low Reset
    
    // AER Interface
    output wire [23:0] aer_packet,       // 24-bit AER output [ch:timestamp]
    output wire        aer_valid,        // AER packet valid flag
    output wire        audio_done,       // High when ROM playback is finished

    // 🛠️ DEBUG PORTS (Probe these in Waveform Viewer)
    output wire [15:0] debug_rom,        // Raw ROM PCM output
    output wire [15:0] debug_emph,       // Pre-emphasis filter output
    output wire [15:0] debug_env0,       // IHC Envelope for Channel 0 (100Hz Band)
    output wire [15:0] debug_spike_bus   // 16-bit binary spike vector
);

//==========================================================================
// 1. CLOCK DIVIDER / SAMPLE ENABLE GENERATOR (16 kHz)
//==========================================================================
reg [12:0] sample_cnt;
wire       sample_en = (sample_cnt == 13'd6249);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        sample_cnt <= 13'd0;
    else
        sample_cnt <= sample_en ? 13'd0 : sample_cnt + 13'd1;
end

//==========================================================================
// 2. AUDIO ROM (Source)
//==========================================================================
wire [15:0] rom_pcm;
wire        rom_valid;
wire        rom_done;

// Align sample_en to ROM output latency (1 cycle delay)
reg rom_valid_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rom_valid_r <= 1'b0;
    else
        rom_valid_r <= sample_en;
end
assign rom_valid = rom_valid_r;

audio_rom #(.N_SAMPLES(20160)) u_audio_rom (
    .clk       (clk),
    .rst_n     (rst_n),
    .sample_en (sample_en),
    .x_out     (rom_pcm),
    .done      (rom_done)
);
assign debug_rom  = rom_pcm; // Connect debug port
assign audio_done = rom_done;

//==========================================================================
// 3. PRE-EMPHASIS FILTER
// FIX: Connected using x_n / y_n ports as per hardware spec
//==========================================================================
wire [15:0] emph_out;
wire        emph_valid;

pm_filter u_emph (
    .clk      (clk),
    .rst_n    (rst_n),
    .valid_in (rom_valid),
    .x_n      (rom_pcm),   // ← Fixed Port Name
    .y_n      (emph_out)   // ← Fixed Port Name
);

// Align valid signal for pipeline
reg emph_valid_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        emph_valid_r <= 1'b0;
    else
        emph_valid_r <= rom_valid;
end
assign emph_valid = emph_valid_r;
assign debug_emph = emph_out; // Connect debug port

//==========================================================================
// 4. IHC SYSTEM (FFT Filterbank + 16× IHC Channels)
//==========================================================================
wire [255:0] envelope_packed;
wire         ihc_valid;

ihc_top u_ihc_system (
    .clk          (clk),
    .rst_n        (rst_n),
    .sample_en    (emph_valid),
    .audio_in     (emph_out),
    .envelope_out (envelope_packed),
    .valid_out    (ihc_valid)
);

// Slice packed vector for LIF inputs
wire [15:0] env_ch0,  env_ch1,  env_ch2,  env_ch3;
wire [15:0] env_ch4,  env_ch5,  env_ch6,  env_ch7;
wire [15:0] env_ch8,  env_ch9,  env_ch10, env_ch11;
wire [15:0] env_ch12, env_ch13, env_ch14, env_ch15;

assign env_ch0  = envelope_packed[15:0];
assign env_ch1  = envelope_packed[31:16];
assign env_ch2  = envelope_packed[47:32];
assign env_ch3  = envelope_packed[63:48];
assign env_ch4  = envelope_packed[79:64];
assign env_ch5  = envelope_packed[95:80];
assign env_ch6  = envelope_packed[111:96];
assign env_ch7  = envelope_packed[127:112];
assign env_ch8  = envelope_packed[143:128];
assign env_ch9  = envelope_packed[159:144];
assign env_ch10 = envelope_packed[175:160];
assign env_ch11 = envelope_packed[191:176];
assign env_ch12 = envelope_packed[207:192];
assign env_ch13 = envelope_packed[223:208];
assign env_ch14 = envelope_packed[239:224];
assign env_ch15 = envelope_packed[255:240];

assign debug_env0 = env_ch0; // Connect debug port (Ch0)

//==========================================================================
// 5. LIF SYSTEM (16 Neurons + AER Encoder)
// FIX: spike_bus must be [15:0] to match aer_encoder input
//==========================================================================
wire [15:0] spike_bus;

lif_top #(
    .LEAK_FACTOR (15'd31130),
    .THRESHOLD   (32'd16000),
    .REFRAC      (4'd8)
) u_lif_system (
    .clk        (clk),
    .rst_n      (rst_n),
    .sample_en  (ihc_valid),
    .ihc_ch1    (env_ch0),
    .ihc_ch2    (env_ch1),
    .ihc_ch3    (env_ch2),
    .ihc_ch4    (env_ch3),
    .ihc_ch5    (env_ch4),
    .ihc_ch6    (env_ch5),
    .ihc_ch7    (env_ch6),
    .ihc_ch8    (env_ch7),
    .ihc_ch9    (env_ch8),
    .ihc_ch10   (env_ch9),
    .ihc_ch11   (env_ch10),
    .ihc_ch12   (env_ch11),
    .ihc_ch13   (env_ch12),
    .ihc_ch14   (env_ch13),
    .ihc_ch15   (env_ch14),
    .ihc_ch16   (env_ch15),
    .data       (aer_packet),
    .aer_valid  (aer_valid),
    .aer_ready  (1'b1),
    .spike_bus  (spike_bus)
);
assign debug_spike_bus = spike_bus; // Connect debug port

endmodule
