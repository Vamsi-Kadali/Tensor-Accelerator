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

parameter WIDTH=16;
parameter ACC=32;
parameter N_MAX=8;
parameter LANES=2;

parameter M=4;
parameter K=4;
parameter N=4;

reg clk;
reg rst;
reg start;

reg [2:0] op;
reg signed [WIDTH-1:0] scalar = '0;

reg [$clog2(M+1)-1:0] M_len;
reg [$clog2(K+1)-1:0] K_len;
reg [$clog2(N+1)-1:0] N_len;

reg signed [WIDTH-1:0] A [0:M-1][0:K-1];
reg signed [WIDTH-1:0] B [0:K-1][0:N-1];

wire signed [ACC-1:0] C [0:M-1][0:N-1];
wire done;

matrix_cont #(WIDTH,ACC,N_MAX,LANES,M,K,N) dut(
    .clk(clk),
    .rst(rst),
    .start(start),
    .op(op),
    .scalar(scalar),
    .M_len(M_len),
    .K_len(K_len),
    .N_len(N_len),
    .A(A),
    .B(B),
    .C(C),
    .done(done)
);

always #5 clk = ~clk;

initial begin

clk=0;
rst=1;
start=0;

#20 rst=0;

////////////////////////
// TEST 1 (2x3 * 3x2)
////////////////////////

M_len=2;
K_len=3;
N_len=2;

A[0][0]=1; A[0][1]=2; A[0][2]=3;
A[1][0]=4; A[1][1]=5; A[1][2]=6;

B[0][0]=7; B[0][1]=8;
B[1][0]=9; B[1][1]=10;
B[2][0]=11; B[2][1]=12;

op=3'b000;

#10 start=1;
#10 start=0;

wait(done);

$display("2x3 * 3x2");
$display("%d %d",C[0][0],C[0][1]);
$display("%d %d",C[1][0],C[1][1]);

////////////////////////
// TEST 2 (1x3 * 3x1)
////////////////////////

M_len=1;
K_len=3;
N_len=1;

A[0][0]=2; A[0][1]=4; A[0][2]=6;

B[0][0]=1;
B[1][0]=2;
B[2][0]=3;

op=3'b000;

#10 start=1;
#10 start=0;

wait(done);

$display("1x3 * 3x1");
$display("%d",C[0][0]);

////////////////////////
// TEST 3 ADD (3x2)
////////////////////////

M_len=3;
K_len=2;
N_len=2;

A[0][0]=1; A[0][1]=2;
A[1][0]=3; A[1][1]=4;
A[2][0]=5; A[2][1]=6;

B[0][0]=7; B[0][1]=8;
B[1][0]=9; B[1][1]=10;
B[2][0]=11; B[2][1]=12;

op=3'b001;

#10 start=1;
#10 start=0;

wait(done);

$display("ADD 3x2");
$display("%d %d",C[0][0],C[0][1]);
$display("%d %d",C[1][0],C[1][1]);
$display("%d %d",C[2][0],C[2][1]);

////////////////////////
// TEST 4 SUB (2x2)
////////////////////////

M_len=2;
K_len=2;
N_len=2;

A[0][0]=10; A[0][1]=20;
A[1][0]=30; A[1][1]=40;

B[0][0]=4;  B[0][1]=5;
B[1][0]=6;  B[1][1]=7;

op=3'b010;

#10 start=1;
#10 start=0;

wait(done);

$display("SUB 2x2");
$display("%d %d",C[0][0],C[0][1]);
$display("%d %d",C[1][0],C[1][1]);

////////////////////////
// TEST 5 SCALAR MULT (2x3)
////////////////////////

M_len=2;
K_len=3;
N_len=3;

scalar = 3;

A[0][0]=1; A[0][1]=2; A[0][2]=3;
A[1][0]=4; A[1][1]=5; A[1][2]=6;

op=3'b011;

#10 start=1;
#10 start=0;

wait(done);

$display("SCALAR MULT 2x3");
$display("%d %d %d",C[0][0],C[0][1],C[0][2]);
$display("%d %d %d",C[1][0],C[1][1],C[1][2]);

////////////////////////
// TEST 6 EDGE CASE 1x1 MULT
////////////////////////

M_len=1;
K_len=1;
N_len=1;

A[0][0]=5;
B[0][0]=7;

op=3'b000;

#10 start=1;
#10 start=0;

wait(done);

$display("EDGE 1x1 MULT");
$display("%d",C[0][0]);

////////////////////////
// TEST 7 EDGE CASE 1x1 SCALAR MULT
////////////////////////

M_len=1;
K_len=1;
N_len=1;

scalar = 4;

A[0][0]=3;

op=3'b011;

#10 start=1;
#10 start=0;

wait(done);

$display("EDGE 1x1 SCALAR MULT");
$display("%d",C[0][0]);

$finish;

end

endmodule