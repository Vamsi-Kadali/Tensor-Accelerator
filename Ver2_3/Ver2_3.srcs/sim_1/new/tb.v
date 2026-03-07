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

    // Parameters for stress test
    parameter M=4;
    parameter K=8;
    parameter N=4;
    parameter WIDTH=16;
    parameter ACC=32;
    parameter N_MAX=3;   // small tile to stress tile logic
    parameter LANES=2;   // small lane count to stress leftover lanes

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;

    reg [2:0] op;
    reg signed [WIDTH-1:0] scalar;

    reg [$clog2(M+1)-1:0] M_len = M;
    reg [$clog2(K+1)-1:0] K_len = K;
    reg [$clog2(N+1)-1:0] N_len = N;

    reg signed [WIDTH-1:0] A [0:M-1][0:K-1];
    reg signed [WIDTH-1:0] B [0:K-1][0:N-1];

    wire signed [ACC-1:0] C [0:M-1][0:N-1];
    wire done;

    // Instantiate the matrix accelerator
    matrix_cont #(WIDTH,ACC,N_MAX,LANES,M,K,N) dut (
        clk, rst, start, op, scalar, M_len, K_len, N_len, A, B, C, done
    );

    integer i,j;

    initial begin
        // 1️⃣ Initialize large matrices with deterministic pattern
        for(i=0;i<M;i=i+1) begin
            for(j=0;j<K;j=j+1) begin
                A[i][j] = i*10 + j + 1;  // just to get different numbers
            end
        end

        for(i=0;i<K;i=i+1) begin
            for(j=0;j<N;j=j+1) begin
                B[i][j] = i + j*2; // different pattern
            end
        end

        scalar = 3;

        // 2️⃣ Reset
        #20 rst = 1;
        #10 rst = 0;

        // ---------------------
        // 3️⃣ MAC (Matrix multiply)
        // ---------------------
        op = 3'b000;
        #10 start = 1;
        #10 start = 0;
        wait(done);

        $display("=== MAC Result ===");
        for(i=0;i<M;i=i+1) begin
            $write("Row %0d: ", i);
            for(j=0;j<N;j=j+1)
                $write("%0d ", C[i][j]);
            $display("");
        end

        // ---------------------
        // 4️⃣ ADD (Elementwise)
        // ---------------------
        op = 3'b001;
        #10 start = 1;
        #10 start = 0;
        wait(done);

        $display("=== ADD Result ===");
        for(i=0;i<M;i=i+1) begin
            $write("Row %0d: ", i);
            for(j=0;j<N;j=j+1)
                $write("%0d ", C[i][j]);
            $display("");
        end

        // ---------------------
        // 5️⃣ SUB (Elementwise)
        // ---------------------
        op = 3'b010;
        #10 start = 1;
        #10 start = 0;
        wait(done);

        $display("=== SUB Result ===");
        for(i=0;i<M;i=i+1) begin
            $write("Row %0d: ", i);
            for(j=0;j<N;j=j+1)
                $write("%0d ", C[i][j]);
            $display("");
        end

        // ---------------------
        // 6️⃣ Scalar multiply
        // ---------------------
        op = 3'b011;
        #10 start = 1;
        #10 start = 0;
        wait(done);

        $display("=== Scalar Multiply Result ===");
        for(i=0;i<M;i=i+1) begin
            $write("Row %0d: ", i);
            for(j=0;j<N;j=j+1)
                $write("%0d ", C[i][j]);
            $display("");
        end

        // ---------------------
        // 7️⃣ SUM across K
        // ---------------------
        op = 3'b100;
        #10 start = 1;
        #10 start = 0;
        wait(done);

        $display("=== SUM across K Result ===");
        for(i=0;i<M;i=i+1) begin
            $write("Row %0d: ", i);
            for(j=0;j<N;j=j+1)
                $write("%0d ", C[i][j]);
            $display("");
        end

        $finish;
    end

endmodule