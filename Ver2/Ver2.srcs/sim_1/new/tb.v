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
parameter M = 4;
parameter K = 8;
parameter N = 4;

reg clk;
reg rst;
reg start;

reg signed [WIDTH-1:0] A [0:M-1][0:K-1];
reg signed [WIDTH-1:0] B [0:K-1][0:N-1];

wire signed [ACC-1:0] C [0:M-1][0:N-1];
wire done;


matrix_cont uut(
    .clk(clk),
    .rst(rst),
    .start(start),
    .A(A),
    .B(B),
    .C(C),
    .done(done)
);


always #5 clk = ~clk;


initial begin
    clk = 0;
    rst = 1;
    start = 0;

    #20 rst = 0;

    // Matrix A
    A[0] = '{1,2,3,4,5,6,7,8};
    A[1] = '{2,1,0,1,2,3,4,5};
    A[2] = '{3,1,2,0,1,2,3,4};
    A[3] = '{1,0,1,0,1,0,1,0};

    // Matrix B
    B[0] = '{1,2,3,4};
    B[1] = '{0,1,0,1};
    B[2] = '{1,0,1,0};
    B[3] = '{2,1,2,1};
    B[4] = '{0,1,0,1};
    B[5] = '{1,2,3,4};
    B[6] = '{2,0,1,0};
    B[7] = '{1,1,1,1};

    #10 start = 1;
    #10 start = 0;

    wait(done);

    $display("Result Matrix C:");

    for(int i=0;i<M;i++) begin
        for(int j=0;j<N;j++) begin
            $write("%0d ",C[i][j]);
        end
        $display("");
    end

    #50 $finish;
end

endmodule