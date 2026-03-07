`timescale 1ns / 1ps

module mac #(
    parameter WIDTH = 16,
    parameter ACC   = 32
)(
    input  logic signed [WIDTH-1:0] a,
    input  logic signed [WIDTH-1:0] b,
    input  logic signed [ACC-1:0] acc_in,
    output logic signed [ACC-1:0] acc_out
);

    // multiplication result
    logic signed [2*WIDTH-1:0] mult;

    assign mult = a * b;

    // force DSP usage on FPGA
    (* use_dsp = "yes" *)
    assign acc_out = acc_in + {{(ACC-2*WIDTH){mult[2*WIDTH-1]}}, mult};

endmodule
