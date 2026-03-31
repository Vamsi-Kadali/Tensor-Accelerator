`timescale 1ns / 1ps

module mac #( parameter WIDTH = 16, parameter ACC = 32 )(
    input  signed [WIDTH-1:0] a,
    input  signed [WIDTH-1:0] b,
    input  signed [ACC-1:0] acc_in,
    output signed [ACC-1:0] acc_out
    );
    assign acc_out = acc_in + (a * b);
endmodule
