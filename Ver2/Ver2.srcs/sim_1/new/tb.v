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
parameter N_MAX=32;
parameter LANES=2;

parameter M=16;
parameter K=16;
parameter N=32;

reg clk;
reg rst;
reg start;

reg [2:0] op;
reg signed [WIDTH-1:0] scalar='0;

reg [$clog2(M+1)-1:0] M_len;
reg [$clog2(K+1)-1:0] K_len;
reg [$clog2(N+1)-1:0] N_len;

reg signed [WIDTH-1:0] A [0:M-1][0:K-1];
reg signed [WIDTH-1:0] B [0:K-1][0:N-1];

wire signed [ACC-1:0] C [0:M-1][0:N-1];
wire done;

integer i,j;

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

////////////////////////////
// TEST : 13x7 * 7x17
////////////////////////////

M_len=13;
K_len=7;
N_len=17;

for(i=0;i<M_len;i=i+1)
for(j=0;j<K_len;j=j+1)
A[i][j]=i+j+1;

for(i=0;i<K_len;i=i+1)
for(j=0;j<N_len;j=j+1)
B[i][j]=i+j+1;

op=3'b000;

#10 start=1;
#10 start=0;

wait(done);

$display("Result Matrix (13x17)");

for(i=0;i<M_len;i=i+1) begin
    for(j=0;j<N_len;j=j+1)
        $write("%d ",C[i][j]);
    $display("");
end

$finish;

end

endmodule