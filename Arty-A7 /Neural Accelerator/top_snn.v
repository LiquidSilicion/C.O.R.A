module top_snn (
    input  wire clk,
    input  wire rst,
    input  wire start,
    output wire done
);

//////////////////////////////////////////////////////////////
// Memory Bus
//////////////////////////////////////////////////////////////

reg         mem_we;
reg  [15:0] mem_addr;
reg  [31:0] mem_wdata;
wire [31:0] mem_rdata;

//////////////////////////////////////////////////////////////
// Internal Signals
//////////////////////////////////////////////////////////////

reg  [3:0] neuron_idx;
reg  [3:0] input_idx;
reg  [4:0] mac_cycle;

reg signed [31:0] accumulator;
reg signed [15:0] weight_data;
reg signed [15:0] input_data;

reg [15:0] v_old;
reg [15:0] v_new;

reg [7:0] threshold;

reg spike;
reg done_reg;
assign done = done_reg;

reg [3:0] state;

//////////////////////////////////////////////////////////////
// FSM States
//////////////////////////////////////////////////////////////

localparam S_IDLE            = 4'd0;
localparam S_READ_CFG_ADDR   = 4'd1;
localparam S_READ_CFG_WAIT   = 4'd2;
localparam S_READ_V_ADDR     = 4'd3;
localparam S_READ_V_WAIT     = 4'd4;
localparam S_MAC             = 4'd5;
localparam S_UPDATE          = 4'd6;
localparam S_WRITE_V         = 4'd7;
localparam S_DONE            = 4'd8;

//////////////////////////////////////////////////////////////
// Example Input Vector
//////////////////////////////////////////////////////////////

wire signed [255:0] input_vec;

assign input_vec = {
    16'd15,16'd14,16'd13,16'd12,
    16'd11,16'd10,16'd9,16'd8,
    16'd7,16'd6,16'd5,16'd4,
    16'd3,16'd2,16'd1,16'd0
};

//////////////////////////////////////////////////////////////
// Memory Controller
//////////////////////////////////////////////////////////////

snn_mem_controller u_mem (
    .clk(clk),
    .we(mem_we),
    .addr(mem_addr),
    .wdata(mem_wdata),
    .rdata(mem_rdata)
);

//////////////////////////////////////////////////////////////
// MAIN FSM
//////////////////////////////////////////////////////////////

always @(posedge clk) begin

    if (rst) begin
        state       <= S_IDLE;
        neuron_idx  <= 0;
        input_idx   <= 0;
        mac_cycle   <= 0;
        accumulator <= 0;
        mem_we      <= 0;
        done_reg    <= 0;
        spike       <= 0;
        threshold   <= 0;
    end

    else begin
        case (state)

        //////////////////////////////////////////////////////
        // IDLE
        //////////////////////////////////////////////////////
        S_IDLE: begin
            done_reg <= 0;
            mem_we   <= 0;

            if (start) begin
                neuron_idx <= 0;
                state      <= S_READ_CFG_ADDR;
            end
        end

        //////////////////////////////////////////////////////
        // READ CONFIG (BANK0 @ 0x0008)
        //////////////////////////////////////////////////////
        S_READ_CFG_ADDR: begin
            mem_we   <= 0;
            mem_addr <= 16'h0008;
            state    <= S_READ_CFG_WAIT;
        end

        S_READ_CFG_WAIT: begin
            threshold <= mem_rdata[23:16];   // θ field
            state     <= S_READ_V_ADDR;
        end

        //////////////////////////////////////////////////////
        // READ V_MEM
        //////////////////////////////////////////////////////
        S_READ_V_ADDR: begin
            mem_we   <= 0;
            mem_addr <= 16'hE000 + (neuron_idx << 2);
            state    <= S_READ_V_WAIT;
        end

        S_READ_V_WAIT: begin
            v_old       <= mem_rdata[15:0];
            accumulator <= 0;
            mac_cycle   <= 0;
            input_idx   <= 0;
            state       <= S_MAC;
        end

        //////////////////////////////////////////////////////
        // SEQUENTIAL MAC
        //////////////////////////////////////////////////////
        S_MAC: begin

            if (mac_cycle < 16) begin
                mem_addr  <= 16'h4000 + (neuron_idx << 4) + mac_cycle[3:0];
                mem_we    <= 0;
            end

            weight_data <= mem_rdata[15:0];
            input_data  <= input_vec[mac_cycle[3:0]*16 +: 16];

            if (mac_cycle > 0 && mac_cycle <= 16) begin
                accumulator <= accumulator + (weight_data * input_data);
            end

            mac_cycle <= mac_cycle + 1;

            if (mac_cycle == 17)
                state <= S_UPDATE;
        end

        //////////////////////////////////////////////////////
        // LIF UPDATE
        //////////////////////////////////////////////////////
        S_UPDATE: begin

            if ((v_old + accumulator[15:0]) >= threshold) begin
                v_new <= 0;
                spike <= 1;
            end
            else begin
                v_new <= v_old + accumulator[15:0];
                spike <= 0;
            end

            state <= S_WRITE_V;
        end

        //////////////////////////////////////////////////////
        // WRITE BACK V_MEM
        //////////////////////////////////////////////////////
        S_WRITE_V: begin
            mem_addr  <= 16'hE000 + (neuron_idx << 2);
            mem_wdata <= {16'd0, v_new};
            mem_we    <= 1;
            state     <= S_DONE;
        end

        //////////////////////////////////////////////////////
        // NEXT NEURON / FINISH
        //////////////////////////////////////////////////////
        S_DONE: begin
            mem_we <= 0;

            if (neuron_idx == 4'd15) begin
                done_reg <= 1;
                state    <= S_IDLE;
            end
            else begin
                neuron_idx <= neuron_idx + 1;
                state      <= S_READ_V_ADDR;
            end
        end

        endcase
    end
end

endmodule
