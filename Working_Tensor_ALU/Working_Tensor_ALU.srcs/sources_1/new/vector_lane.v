`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.03.2026 12:40:58
// Design Name: 
// Module Name: vector_lane
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


module vector_lane #( parameter WIDTH = 16, ACC = 32, N_MAX = 64 )(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,
    input scalar_en,

    input [$clog2(N_MAX+1)-1:0] vec_len,

    input signed [WIDTH-1:0] a [0:N_MAX-1],
    input signed [WIDTH-1:0] b [0:N_MAX-1],

    output reg signed [ACC-1:0] res,
    output reg done
);


    localparam ID_W = (N_MAX <= 1) ? 1 : $clog2(N_MAX);

    localparam
        OP_MAC = 3'b000,
        OP_ADD = 3'b001,
        OP_SUB = 3'b010,
        OP_MUL = 3'b011,
        OP_SUM = 3'b100;


    reg [ID_W-1:0] id;

    reg signed [ACC-1:0] acc_reg;
    wire signed [ACC-1:0] acc_next;

    reg signed [WIDTH-1:0] a_reg [0:N_MAX-1];
    reg signed [WIDTH-1:0] b_reg [0:N_MAX-1];

    integer i;


    wire signed [WIDTH-1:0] a_sel = a_reg[id];
    wire signed [WIDTH-1:0] b_sel = scalar_en ? b_reg[0] : b_reg[id];


    reg signed [WIDTH-1:0] a_eff;
    reg signed [WIDTH-1:0] b_eff;
    reg signed [ACC-1:0]   acc_eff;

    always @(*) begin
        a_eff = a_sel;
        b_eff = b_sel;
        acc_eff = acc_reg;

        case (op)
            OP_MAC: begin
            end

            OP_MUL: begin
                acc_eff = 0;
            end

            OP_ADD: begin
                b_eff   = 1;
                acc_eff = b_sel;
            end

            OP_SUB: begin
                b_eff   = 1;
                acc_eff = -b_sel;
            end

            OP_SUM: begin
                b_eff = 1;
            end

            default: begin
                acc_eff = acc_reg;
            end
        endcase
    end

    mac #(WIDTH, ACC) mac_inst ( .a(a_eff), .b(b_eff), .acc_in(acc_eff), .acc_out(acc_next) );


    always @(posedge clk) begin
        if (rst) begin
            id <= '0;
            acc_reg <= '0;
            res <= '0;
            done <= 1'b0;

            for (i = 0; i < N_MAX; i = i + 1) begin
                a_reg[i] <= '0;
                b_reg[i] <= '0;
            end
        end

        else if (load) begin
            id <= '0;
            acc_reg <= '0;
            res <= '0;
            done <= 1'b0;

            for (i = 0; i < vec_len; i = i + 1) begin
                a_reg[i] <= a[i];
                b_reg[i] <= b[i];
            end
        end

        else if (en && !done && vec_len!=0) begin
            acc_reg <= acc_next;

            if (id == vec_len - 1) begin
                res <= acc_next;
                done <= 1'b1;
                id <= '0;
            end
            else begin
                id <= id + 1;
            end
        end
    end

endmodule