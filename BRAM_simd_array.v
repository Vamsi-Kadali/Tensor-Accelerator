`timescale 1ns / 1ps

module simd_array #(
    parameter WIDTH = 16,
    parameter ACC   = 32,
    parameter N_MAX = 4,
    parameter LANES = 4
)(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,
    input scalar_en,
    input [$clog2(N_MAX+1)-1:0] vec_len,

    // one element per lane from BRAM
    input signed [WIDTH-1:0] a [LANES],
    input signed [WIDTH-1:0] b [LANES],

    output signed [ACC-1:0] res [LANES],
    output done
);

  
    wire [LANES-1:0] lane_done;

    
    genvar i;

    generate
        for (i = 0; i < LANES; i = i + 1) begin : SIMD_LANES

            vector_lane #(
                .WIDTH(WIDTH),
                .ACC(ACC),
                .N_MAX(N_MAX)
            ) lane (

                .clk(clk),
                .rst(rst),
                .load(load),
                .en(en),

                .op(op),
                .scalar_en(scalar_en),
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
