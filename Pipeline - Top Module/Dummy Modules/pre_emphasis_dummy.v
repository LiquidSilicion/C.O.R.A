module pre_emphasis_dummy(
    input wire clk,
    input wire rst_n,
    input wire data_valid,
    input wire data_in,
    output reg [14:0]data_out);
    
    always@(posedge clk or negedge rst_n)
        if(!rst_n)begin
            data_out<=0;
        end else begin
            if(data_valid)begin
                data_out<= data_in;
            end
     end
endmodule
