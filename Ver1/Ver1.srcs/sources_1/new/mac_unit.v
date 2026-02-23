`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.02.2026 18:44:59
// Design Name: 
// Module Name: mac_unit
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mac #( parameter WIDTH = 16, parameter ACC = 32 )(
    input clk,
    input rst,
    input en,
    input signed [WIDTH-1:0] a,
    input signed [WIDTH-1:0] b,
    input signed [ACC-1:0] acc_in,
    output reg signed [ACC-1:0] acc_out
    );
    
    wire signed [2*WIDTH-1:0] mult_res;
    
    assign mult_res = a * b;
    
    always @(posedge clk) begin
        if(rst)
            acc_out <= 'b0;
        
        else if (en)
            acc_out <= acc_in + mult_res;
       
    end
endmodule
