module ihc_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_en,
    input  wire signed [15:0] audio_in,
    output wire [255:0] envelope_out,
    
    output wire        valid_out
);

    // 1. Internal unpacked array for clean generate-loop wiring
    wire [15:0] env_int [0:15];
    
    // 2. BPF wires & packing (unchanged from before)
    wire signed [15:0] y_ch1,  y_ch2,  y_ch3,  y_ch4;
    wire signed [15:0] y_ch5,  y_ch6,  y_ch7,  y_ch8;
    wire signed [15:0] y_ch9,  y_ch10, y_ch11, y_ch12;
    wire signed [15:0] y_ch13, y_ch14, y_ch15, y_ch16;
    wire signed [15:0] bpf_out [0:15];
    assign bpf_out[0]=y_ch1;  assign bpf_out[1]=y_ch2;  assign bpf_out[2]=y_ch3;  assign bpf_out[3]=y_ch4;
    assign bpf_out[4]=y_ch5;  assign bpf_out[5]=y_ch6;  assign bpf_out[6]=y_ch7;  assign bpf_out[7]=y_ch8;
    assign bpf_out[8]=y_ch9;  assign bpf_out[9]=y_ch10; assign bpf_out[10]=y_ch11; assign bpf_out[11]=y_ch12;
    assign bpf_out[12]=y_ch13;assign bpf_out[13]=y_ch14;assign bpf_out[14]=y_ch15;assign bpf_out[15]=y_ch16;

    // 3. BPF instance (unchanged)
    wire bpf_valid;
    fft_filterbank #(.SB(16), .CB(16)) u_filterbank (
        .clk(clk), .rst_n(rst_n), .sample_en(sample_en), .x_in(audio_in),
        .y_ch1(y_ch1), .y_ch2(y_ch2), .y_ch3(y_ch3), .y_ch4(y_ch4),
        .y_ch5(y_ch5), .y_ch6(y_ch6), .y_ch7(y_ch7), .y_ch8(y_ch8),
        .y_ch9(y_ch9), .y_ch10(y_ch10), .y_ch11(y_ch11), .y_ch12(y_ch12),
        .y_ch13(y_ch13), .y_ch14(y_ch14), .y_ch15(y_ch15), .y_ch16(y_ch16),
        .y_valid(bpf_valid)
    );

    // 4. Generate loop connects to INTERNAL array
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : ihc_array
            ihc_channel u_ihc_ch (
                .clk      (clk),
                .rst_n      (rst_n),
                .valid_in (bpf_valid),
                .x_in     (bpf_out[i]),
                .y_out    (env_int[i])  // ← Maps to internal array, NOT port directly
            );
        end
    endgenerate

    // 5. Pack internal array → wide output port
    assign envelope_out[15:0]   = env_int[0];
    assign envelope_out[31:16]  = env_int[1];
    assign envelope_out[47:32]  = env_int[2];
    assign envelope_out[63:48]  = env_int[3];
    assign envelope_out[79:64]  = env_int[4];
    assign envelope_out[95:80]  = env_int[5];
    assign envelope_out[111:96] = env_int[6];
    assign envelope_out[127:112]= env_int[7];
    assign envelope_out[143:128]= env_int[8];
    assign envelope_out[159:144]= env_int[9];
    assign envelope_out[175:160]= env_int[10];
    assign envelope_out[191:176]= env_int[11];
    assign envelope_out[207:192]= env_int[12];
    assign envelope_out[223:208]= env_int[13];
    assign envelope_out[239:224]= env_int[14];
    assign envelope_out[255:240]= env_int[15];

    reg [3:0] valid_shift;
    always @(posedge clk) begin
        if (!rst_n)
            valid_shift <= 4'b0000;
        else
            valid_shift <= {valid_shift[2:0], bpf_valid}; // Shift left, inject new at [0]
        end
        assign valid_out = valid_shift[3]; // Output aligns exactly with envelope_out data

endmodule
