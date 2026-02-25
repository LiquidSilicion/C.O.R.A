module i2s_dummy(
    input wire clk,
    input wire rst_n,
    input wire data_valid,
    input wire data_in,
    output reg data_ready,
    output reg [15:0] i2s_data_out);
    
    always@(posedge clk or negedge rst_n)
        if(!rst_n)begin
            i2s_data_out<=0;
        end else begin
            if(data_valid)begin
                i2s_data_out<= data_in;   
            end
     end
endmodule

