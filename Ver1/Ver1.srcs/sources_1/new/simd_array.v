`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.02.2026 21:42:17
// Design Name: 
// Module Name: simd_array
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


module simd_array #( parameter WIDTH = 16, parameter ACC = 32, parameter N_MAX = 4, parameter LANES = 4)(
    input clk,
    input rst,
    input load,
    input en,
    
    input [$clog2(N_MAX+1)-1:0] vec_len,
    
    input signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1],
    input signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1],
    
    output signed [ACC-1:0] res [0:LANES-1],
    output done
    );

    wire [LANES-1:0] lane_done;

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : SIMD_LANES
            baseline_mac #( WIDTH, ACC, N_MAX ) lane ( clk, rst, load, en, vec_len, a[i], b[i], res[i], lane_done[i] );
        end
    endgenerate

    assign done = &lane_done;

endmodule