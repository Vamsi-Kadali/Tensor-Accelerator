`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.02.2026 13:46:48
// Design Name: 
// Module Name: test
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

// Top-level wrapper with internal unpacking
// Dummy top using your modules
module test #(
    parameter WIDTH = 16,
    parameter ACC   = 32,
    parameter N_MAX = 4,
    parameter LANES = 4,
    parameter N_W   = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [1:0] op,

    // Minimal dummy inputs
    input  wire [LANES*WIDTH*N_MAX-1:0] a_bus,
    input  wire [LANES*WIDTH*N_MAX-1:0] b_bus,

    // Outputs
    output wire [LANES*ACC-1:0] res_bus,
    output wire done
);

    // --- Internal unpacked arrays ---
    wire signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1];
    wire signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1];
    wire signed [ACC-1:0] res [0:LANES-1];

    genvar i, j;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : UNPACK_LANES
            for (j = 0; j < N_MAX; j = j + 1) begin : UNPACK_ELEMS
                assign a[i][j] = a_bus[(i*N_MAX+j)*WIDTH +: WIDTH];
                assign b[i][j] = b_bus[(i*N_MAX+j)*WIDTH +: WIDTH];
            end
        end
    endgenerate

    // --- FSM control signals ---
    wire en, clear, datapath_done;

    // --- Instantiate SIMD array ---
    simd_array #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) simd_inst (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .en(en),
        .vec_len(N_MAX),
        .a(a),
        .b(b),
        .res(res),
        .done(datapath_done)
    );

    // --- Instantiate FSM ---
    accel_fsm #(
        .N_W(N_W)
    ) fsm_inst (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .N(N_MAX[N_W-1:0]),
        .datapath_done(datapath_done),
        .en(en),
        .clear(clear),
        .done(done)
    );

    // --- Pack outputs back into bus ---
    generate
        for (i = 0; i < LANES; i = i + 1) begin : PACK_RES
            assign res_bus[i*ACC +: ACC] = res[i];
        end
    endgenerate

endmodule