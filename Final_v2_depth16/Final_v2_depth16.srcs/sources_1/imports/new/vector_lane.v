`timescale 1ns / 1ps

module vector_lane #(
    parameter WIDTH = 16,
    parameter ACC   = 40,
    parameter N_MAX = 64
)(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,

    input [$clog2(N_MAX+1)-1:0] vec_len,

    output [$clog2(N_MAX)-1:0] a_raddr,
    output [$clog2(N_MAX)-1:0] b_raddr,

    input signed [WIDTH-1:0] a_rdata,
    input signed [WIDTH-1:0] b_rdata,

    output reg signed [ACC-1:0] res,
    output reg done
);

    localparam ID_W = (N_MAX <= 1) ? 1 : $clog2(N_MAX);

    localparam
        OP_MATMULT   = 3'b000,
        OP_ADD       = 3'b001,
        OP_SUB       = 3'b010,
        OP_HADAMARD  = 3'b011,
        OP_ROW_ACCUM = 3'b100,
        OP_COL_ACCUM = 3'b101;

    reg [ID_W-1:0]        id;
    reg signed [ACC-1:0]  acc_reg;
    wire signed [ACC-1:0] acc_next;

    assign a_raddr = id;
    assign b_raddr = id;

    reg signed [WIDTH-1:0] a_rdata_r;
    reg signed [WIDTH-1:0] b_rdata_r;

    always @(posedge clk) begin
        a_rdata_r <= a_rdata;
        b_rdata_r <= b_rdata;
    end

    reg en_d1;
    always @(posedge clk) begin
        if (rst || load)
            en_d1 <= 1'b0;
        else
            en_d1 <= en & !done;
    end

    reg id_was_last;
    always @(posedge clk) begin
        if (rst || load)
            id_was_last <= 1'b0;
        else if (en && !done && vec_len != 0)
            id_was_last <= (id == vec_len - 1);
        else
            id_was_last <= 1'b0;
    end

    reg signed [WIDTH-1:0] a_eff;
    reg signed [WIDTH-1:0] b_eff;
    reg signed [ACC-1:0]   acc_eff;

    always @(*) begin
        a_eff   = a_rdata_r;
        b_eff   = b_rdata_r;
        acc_eff = acc_reg;

        case (op)
            OP_MATMULT: begin
            end

            OP_HADAMARD: begin
                acc_eff = 0;
            end

            OP_ADD: begin
                b_eff   = 1;
                acc_eff = b_rdata_r;
            end

            OP_SUB: begin
                b_eff   = 1;
                acc_eff = -b_rdata_r;
            end

            OP_ROW_ACCUM, OP_COL_ACCUM: begin
                b_eff = 1;
            end

            default: begin
                acc_eff = acc_reg;
            end
        endcase
    end

    mac #(WIDTH, ACC) mac_inst (
        .a      (a_eff),
        .b      (b_eff),
        .acc_in (acc_eff),
        .acc_out(acc_next)
    );

    always @(posedge clk) begin
        if (rst) begin
            id      <= '0;
            acc_reg <= '0;
            res     <= '0;
            done    <= 1'b0;
        end
        else if (load) begin
            id      <= '0;
            acc_reg <= '0;
            res     <= '0;
            done    <= 1'b0;
        end
        else if (en && !done && vec_len != 0) begin
            if (id == vec_len - 1)
                id <= '0;
            else
                id <= id + 1;
        end

        if (en_d1 && !done && vec_len != 0) begin
            acc_reg <= acc_next;

            if (id_was_last) begin
                res  <= acc_next;
                done <= 1'b1;
            end
        end
    end

endmodule