`timescale 1ns / 1ps

module vector_lane #(
    parameter WIDTH = 16,
    parameter ACC   = 32,
    parameter N_MAX = 4
)(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,
    input scalar_en,

    input [$clog2(N_MAX+1)-1:0] vec_len,

    // streamed inputs from BRAM
    input signed [WIDTH-1:0] a,
    input signed [WIDTH-1:0] b,

    output reg signed [ACC-1:0] res,
    output reg done
);

   

    localparam
        OP_MAC = 3'b000,
        OP_ADD = 3'b001,
        OP_SUB = 3'b010,
        OP_MUL = 3'b011,
        OP_SUM = 3'b100;

 

    reg signed [ACC-1:0] acc_reg;
    wire signed [ACC-1:0] acc_next;

   

    reg [$clog2(N_MAX+1)-1:0] count;



    reg signed [WIDTH-1:0] a_eff;
    reg signed [WIDTH-1:0] b_eff;
    reg signed [ACC-1:0] acc_eff;

    always @(*) begin

        a_eff = a;
        b_eff = b;
        acc_eff = acc_reg;

        case (op)

            OP_MAC: begin
                // normal MAC
            end

            OP_MUL: begin
                acc_eff = 0;
            end

            OP_ADD: begin
                b_eff   = 1;
                acc_eff = b;
            end

            OP_SUB: begin
                b_eff   = 1;
                acc_eff = -b;
            end

            OP_SUM: begin
                b_eff = 1;
            end

        endcase

    end

    

    mac #(WIDTH, ACC) mac_inst (
        .a(a_eff),
        .b(b_eff),
        .acc_in(acc_eff),
        .acc_out(acc_next)
    );

 -

    always @(posedge clk) begin

        if (rst) begin
            count   <= 0;
            acc_reg <= 0;
            res     <= 0;
            done    <= 0;
        end

        else if (load) begin
            count   <= 0;
            acc_reg <= 0;
            res     <= 0;
            done    <= 0;
        end

        else if (en && !done && vec_len != 0) begin

            acc_reg <= acc_next;

            if (count == vec_len - 1) begin
                res  <= acc_next;
                done <= 1;
            end
            else begin
                count <= count + 1;
            end

        end

    end

endmodule
