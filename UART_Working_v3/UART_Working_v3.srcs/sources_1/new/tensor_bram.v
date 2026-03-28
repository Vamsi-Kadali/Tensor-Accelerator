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
    parameter WIDTH  = 16,
    parameter DEPTH  = 256,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input  clk,
 
    // Port A
    input  we_a,
    input  [ADDR_W-1:0]    addr_a,
    input  signed [WIDTH-1:0] din_a,
    output reg signed [WIDTH-1:0] dout_a,
 
    // Port B
    input  we_b,
    input  [ADDR_W-1:0]    addr_b,
    input  signed [WIDTH-1:0] din_b,
    output reg signed [WIDTH-1:0] dout_b
);
 
    (* ram_style = "block" *)
    reg signed [WIDTH-1:0] mem [0:DEPTH-1];
 
    // Port A - write/read
    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
    end
 
    // Port B - typically read-only in this design
    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end
 
endmodule