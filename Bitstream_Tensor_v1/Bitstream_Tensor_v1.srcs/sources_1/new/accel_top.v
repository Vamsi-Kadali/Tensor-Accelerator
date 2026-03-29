`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.03.2026 15:11:57
// Design Name: 
// Module Name: accel_top
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


module accel_top #( parameter WIDTH = 16, ACC = 38, N_MAX = 64, LANES = 64 )(
    input clk,
    input rst,
    input start,

    input [2:0] op,
    input [$clog2(N_MAX+1)-1:0] vec_len,

    input signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1],
    input signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1],

    output signed [ACC-1:0] res [0:LANES-1],
    output busy,
    output done
);

    wire en;
    wire load;
    wire datapath_done;

    accel_fsm fsm (
        .clk(clk),
        .rst(rst),
        .start(start),
        .datapath_done(datapath_done),
        .en(en),
        .load(load),
        .busy(busy),
        .done(done)
    );

    simd_array #(WIDTH, ACC, N_MAX, LANES) simd (
        .clk(clk),
        .rst(rst),
        .load(load),
        .en(en),
        .op(op),
        .vec_len(vec_len),
        .a(a),
        .b(b),
        .res(res),
        .done(datapath_done)
    );

endmodule