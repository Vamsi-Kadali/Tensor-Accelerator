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

    // NEW: Tile buffer write control signals (from matrix_cont)
    input  [LANES-1:0]                     a_tile_we,
    input  [LANES-1:0][$clog2(N_MAX)-1:0]  a_tile_waddr,
    input  [LANES-1:0][WIDTH-1:0]          a_tile_wdata,

    input  [LANES-1:0]                     b_tile_we,
    input  [LANES-1:0][$clog2(N_MAX)-1:0]  b_tile_waddr,
    input  [LANES-1:0][WIDTH-1:0]          b_tile_wdata,

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

    // NEW: Tile buffer read address/data wires (between simd_array and tile_buf instances)
    wire [LANES-1:0][$clog2(N_MAX)-1:0]  a_raddr, b_raddr;
    wire [LANES-1:0][WIDTH-1:0]          a_rdata, b_rdata;

    simd_array #(WIDTH, ACC, N_MAX, LANES) simd (
        .clk(clk),
        .rst(rst),
        .load(load),
        .en(en),
        .op(op),
        .vec_len(vec_len),
        .a_raddr(a_raddr),
        .a_rdata(a_rdata),
        .b_raddr(b_raddr),
        .b_rdata(b_rdata),
        .res(res),
        .done(datapath_done)
    );

    // NEW: Instantiate tile_buf instances for A and B
    genvar g_lane;
    generate
        for (g_lane = 0; g_lane < LANES; g_lane = g_lane + 1) begin : TILE_BUFFERS_A
            tile_buf #(.WIDTH(WIDTH), .DEPTH(N_MAX)) a_buf (
                .clk(clk),
                .we(a_tile_we[g_lane]),
                .waddr(a_tile_waddr[g_lane]),
                .wdata(a_tile_wdata[g_lane]),
                .raddr(a_raddr[g_lane]),
                .rdata(a_rdata[g_lane])
            );
        end
        for (g_lane = 0; g_lane < LANES; g_lane = g_lane + 1) begin : TILE_BUFFERS_B
            tile_buf #(.WIDTH(WIDTH), .DEPTH(N_MAX)) b_buf (
                .clk(clk),
                .we(b_tile_we[g_lane]),
                .waddr(b_tile_waddr[g_lane]),
                .wdata(b_tile_wdata[g_lane]),
                .raddr(b_raddr[g_lane]),
                .rdata(b_rdata[g_lane])
            );
        end
    endgenerate

endmodule