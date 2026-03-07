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

module tb;

parameter WIDTH = 16;
parameter ACC   = 32;
parameter N_MAX = 8;
parameter LANES = 4;
parameter M = 4;
parameter K = 8;
parameter N = 4;

reg clk;
reg rst;
reg start;

reg [2:0] op;
reg signed [WIDTH-1:0] scalar;

reg [$clog2(M+1)-1:0] M_len;
reg [$clog2(K+1)-1:0] K_len;
reg [$clog2(N+1)-1:0] N_len;

reg signed [WIDTH-1:0] A [0:M-1][0:K-1];
reg signed [WIDTH-1:0] B [0:K-1][0:N-1];

wire signed [ACC-1:0] C [0:M-1][0:N-1];
wire done;

matrix_cont #(WIDTH,ACC,N_MAX,LANES,M,K,N) dut(
    clk,rst,start,
    op,scalar,
    M_len,K_len,N_len,
    A,B,
    C,
    done
);

always #5 clk = ~clk;

task print_C;
begin
    $display("Result Matrix C:");
    for(int i=0;i<M;i++) begin
        for(int j=0;j<N;j++)
            $write("%5d ", C[i][j]);
        $display("");
    end
end
endtask

task run;
begin
    start = 1;
    @(posedge clk);
    start = 0;
    wait(done);
    @(posedge clk);
    print_C();
end
endtask

initial begin

clk = 0;
rst = 1;
start = 0;

#20 rst = 0;

M_len = 4;
K_len = 8;
N_len = 4;

/////////////////////////////////////
// Initialize A
/////////////////////////////////////

A[0] = '{1,2,3,4,5,6,7,8};
A[1] = '{2,3,4,5,6,7,8,9};
A[2] = '{3,4,5,6,7,8,9,10};
A[3] = '{4,5,6,7,8,9,10,11};

/////////////////////////////////////
// Initialize B
/////////////////////////////////////

B[0] = '{1,2,3,4};
B[1] = '{2,3,4,5};
B[2] = '{3,4,5,6};
B[3] = '{4,5,6,7};
B[4] = '{5,6,7,8};
B[5] = '{6,7,8,9};
B[6] = '{7,8,9,10};
B[7] = '{8,9,10,11};

/////////////////////////////////////
// MATRIX MULTIPLY
/////////////////////////////////////

$display("\nMATRIX MULTIPLY");
op = 3'b000;
run();

/////////////////////////////////////
// VECTOR ADD
/////////////////////////////////////

$display("\nVECTOR ADD");
op = 3'b001;
run();

/////////////////////////////////////
// VECTOR SUB
/////////////////////////////////////

$display("\nVECTOR SUB");
op = 3'b010;
run();

/////////////////////////////////////
// VECTOR MUL
/////////////////////////////////////

$display("\nVECTOR MUL");
op = 3'b011;
run();

/////////////////////////////////////
// SCALAR MUL
/////////////////////////////////////

$display("\nSCALAR MUL (scalar=2)");
scalar = 2;
op = 3'b011;
run();

/////////////////////////////////////
// VECTOR SUM
/////////////////////////////////////

$display("\nVECTOR SUM");
op = 3'b100;
run();

/////////////////////////////////////
// TILING TEST
/////////////////////////////////////

$display("\nTILING TEST (smaller sizes)");
M_len = 3;
K_len = 5;
N_len = 3;

op = 3'b000;
run();

#50 $finish;

end

endmodule
