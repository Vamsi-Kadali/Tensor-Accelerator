`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.02.2026 00:26:26
// Design Name: 
// Module Name: accel_ctrl
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


module accel_ctrl #( parameter N_W = 8 )(
    input clk,
    input rst,
    input cmd_valid,
    input [1:0]cmd_op,
    input [N_W-1:0] cmd_N,
    input fsm_done,
    output reg fsm_start,
    output reg [1:0]  fsm_op,
    output reg [N_W-1:0] fsm_N,
    output reg busy,
    output reg done
    );
    
    
endmodule
