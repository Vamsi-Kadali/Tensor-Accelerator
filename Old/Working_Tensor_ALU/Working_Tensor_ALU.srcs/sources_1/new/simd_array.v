`timescale 1ns / 1ps

module simd_array #( parameter WIDTH = 16, ACC = 32, N_MAX = 64, LANES = 64 )(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,
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
            vector_lane #(WIDTH, ACC, N_MAX) lane (
            .clk(clk),
            .rst(rst),
            .load(load),
            .en(en),
            .op(op),
            .vec_len(vec_len),
            .a(a[i]),
            .b(b[i]),
            .res(res[i]),
            .done(lane_done[i])
            );
        end
    endgenerate

    assign done = &lane_done;

endmodule
