`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.03.2026 20:34:34
// Design Name: 
// Module Name: tensor_bram
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


module tensor_bram #(
    parameter WIDTH = 16,
    parameter DEPTH = 4096,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input clk,
    input en,
    input we,
    input [ADDR_W-1:0] addr,
    input signed [WIDTH-1:0] din,
    output reg signed [WIDTH-1:0] dout
);

    (* ram_style = "block" *)
    reg signed [WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (en) begin
            if (we)
                mem[addr] <= din;
            dout <= mem[addr];
        end
    end
    
endmodule
