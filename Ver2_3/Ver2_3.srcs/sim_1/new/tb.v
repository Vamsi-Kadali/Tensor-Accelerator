`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.03.2026 12:53:33
// Design Name: 
// Module Name: tb
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

module tb_addsub;

    // Parameters
    parameter WIDTH = 16;
    parameter ACC   = 32;
    parameter M_MAX = 4;
    parameter N_MAX_MAT = 4;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg [2:0] op;
    reg signed [WIDTH-1:0] scalar;

    reg [$clog2(M_MAX+1)-1:0] M_len;
    reg [$clog2(N_MAX_MAT+1)-1:0] N_len;

    reg signed [WIDTH-1:0] A [0:M_MAX-1][0:N_MAX_MAT-1];
    reg signed [WIDTH-1:0] B [0:M_MAX-1][0:N_MAX_MAT-1];

    wire signed [ACC-1:0] C [0:M_MAX-1][0:N_MAX_MAT-1];
    wire done;

    // Instantiate DUT
    matrix_cont #(WIDTH,ACC,8,4,M_MAX,M_MAX,N_MAX_MAT) dut (
        clk, rst, start, op, scalar, M_len, M_len, N_len, A, B, C, done
    );

    integer i,j;

    initial begin
        // Reset
        #10 rst = 1;
        #10 rst = 0;

        // -------------------------
        // ADD Cases
        // -------------------------
        scalar=0;
        op=3'b001;

        // Max 4x4
        M_len=4; N_len=4;
        A = '{ '{1,2,3,4}, '{5,6,7,8}, '{9,10,11,12}, '{13,14,15,16} };
        B = '{ '{16,15,14,13}, '{12,11,10,9}, '{8,7,6,5}, '{4,3,2,1} };
        #10 start=1; #10 start=0; wait(done);
        $display("ADD Max Case (4x4):");
        for(i=0;i<4;i=i+1) begin
            $write("Row %0d: ",i);
            for(j=0;j<4;j=j+1) $write("%0d ", C[i][j]);
            $display("");
        end

        // Medium 2x2
        M_len=2; N_len=2;
        A = '{ '{10,20}, '{30,40} };
        B = '{ '{1,2}, '{3,4} };
        #10 start=1; #10 start=0; wait(done);
        $display("ADD Medium Case (2x2):");
        for(i=0;i<2;i=i+1) begin
            $write("Row %0d: ",i);
            for(j=0;j<2;j=j+1) $write("%0d ", C[i][j]);
            $display("");
        end

        // -------------------------
        // SUB Cases
        // -------------------------
        op=3'b010;

        // Max 4x4
        M_len=4; N_len=4;
        A = '{ '{10,20,30,40}, '{50,60,70,80}, '{90,100,110,120}, '{130,140,150,160} };
        B = '{ '{1,2,3,4}, '{5,6,7,8}, '{9,10,11,12}, '{13,14,15,16} };
        #10 start=1; #10 start=0; wait(done);
        $display("SUB Max Case (4x4):");
        for(i=0;i<4;i=i+1) begin
            $write("Row %0d: ",i);
            for(j=0;j<4;j=j+1) $write("%0d ", C[i][j]);
            $display("");
        end

        // Medium 2x3
        M_len=2; N_len=3;
        A = '{ '{7,8,9}, '{1,2,3} };
        B = '{ '{3,2,1}, '{9,8,7} };
        #10 start=1; #10 start=0; wait(done);
        $display("SUB Medium Case (2x3):");
        for(i=0;i<2;i=i+1) begin
            $write("Row %0d: ",i);
            for(j=0;j<3;j=j+1) $write("%0d ", C[i][j]);
            $display("");
        end

        $finish;
    end

endmodule