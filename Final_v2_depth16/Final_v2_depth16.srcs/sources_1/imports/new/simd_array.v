`timescale 1ns / 1ps

module simd_array #(
    parameter WIDTH = 16,
    parameter ACC   = 38,
    parameter N_MAX = 64,
    parameter LANES = 64
)(
    input clk,
    input rst,
    input load,
    input en,
    input [2:0] op,
    input [$clog2(N_MAX+1)-1:0] vec_len,

    output [LANES-1:0][$clog2(N_MAX)-1:0] a_raddr,
    input  [LANES-1:0][WIDTH-1:0]          a_rdata,
    output [LANES-1:0][$clog2(N_MAX)-1:0] b_raddr,
    input  [LANES-1:0][WIDTH-1:0]          b_rdata,

    output signed [ACC-1:0] res [0:LANES-1],
    output done
);

    wire [LANES-1:0] lane_done;

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : SIMD_LANES
            vector_lane #(WIDTH, ACC, N_MAX) lane (
                .clk    (clk),
                .rst    (rst),
                .load   (load),
                .en     (en),
                .op     (op),
                .vec_len(vec_len),
                .a_raddr(a_raddr[i]),
                .a_rdata(a_rdata[i]),
                .b_raddr(b_raddr[i]),
                .b_rdata(b_rdata[i]),
                .res    (res[i]),
                .done   (lane_done[i])
            );
        end
    endgenerate

    assign done = &lane_done;

endmodule