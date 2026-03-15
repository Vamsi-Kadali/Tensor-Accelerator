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


module tb_matrix_cont_random;

    parameter WIDTH   = 16;
    parameter ACC     = 40;
    parameter N_MAX   = 64;
    parameter LANES   = 64;
    parameter MAX_DIM = 64;

    parameter TILE_R  = 8;
    parameter TILE_C  = 8;

    reg clk;
    reg rst;
    reg start;

    reg [2:0] op;
    reg signed [WIDTH-1:0] scalar;

    reg [$clog2(MAX_DIM+1)-1:0] M_len;
    reg [$clog2(MAX_DIM+1)-1:0] K_len;
    reg [$clog2(MAX_DIM+1)-1:0] N_len;

    reg signed [WIDTH-1:0] A [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B [0:MAX_DIM-1][0:MAX_DIM-1];

    wire signed [ACC-1:0] C [0:MAX_DIM-1][0:MAX_DIM-1];

    reg signed [ACC-1:0] GOLD [0:MAX_DIM-1][0:MAX_DIM-1];

    wire done;

    integer i,j,k;

    matrix_cont #(
        .WIDTH(WIDTH),
        .N_MAX(N_MAX),
        .LANES(LANES),
        .TILE_R(TILE_R),
        .TILE_C(TILE_C),
        .MAX_DIM(MAX_DIM),
        .ACC(ACC)
    ) DUT (
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

//////////////////////////////////////////////////////////
// RUN TASK
//////////////////////////////////////////////////////////

    task run;
    begin
        start = 1;
        #10 start = 0;
        wait(done);
        #10;
    end
    endtask

//////////////////////////////////////////////////////////
// GOLDEN MODEL
//////////////////////////////////////////////////////////

    task compute_golden;
    integer m,n,k;
    begin
        for(m=0;m<M_len;m=m+1)
        for(n=0;n<N_len;n=n+1)
        begin
            GOLD[m][n] = 0;
            for(k=0;k<K_len;k=k+1)
                GOLD[m][n] = GOLD[m][n] + A[m][k]*B[k][n];
        end
    end
    endtask

//////////////////////////////////////////////////////////
// COMPARE RESULTS
//////////////////////////////////////////////////////////

    task compare_result;
    integer m,n;
    integer errors;
    begin

        errors = 0;

        for(m=0;m<M_len;m=m+1)
        for(n=0;n<N_len;n=n+1)
        begin
            if(C[m][n] !== GOLD[m][n])
            begin
                $display("ERROR (%0d,%0d) DUT=%0d GOLD=%0d",
                         m,n,C[m][n],GOLD[m][n]);
                errors = errors + 1;
            end
        end

        if(errors==0)
            $display("PASS: Random test successful");

        else
            $display("FAIL: %0d mismatches detected",errors);

    end
    endtask


//////////////////////////////////////////////////////////
// TEST
//////////////////////////////////////////////////////////

    initial begin

        clk=0;
        rst=1;
        start=0;

        #20 rst=0;

        op = 3'b000;   // MATRIX MULTIPLY

        // random matrix sizes (within limits)
        M_len = 13;
        K_len = 11;
        N_len = 9;

        // random matrix data
        for(i=0;i<M_len;i=i+1)
        for(j=0;j<K_len;j=j+1)
            A[i][j] = $random;

        for(i=0;i<K_len;i=i+1)
        for(j=0;j<N_len;j=j+1)
            B[i][j] = $random;

        compute_golden();

        run();
        compare_result();
        
        #50 run();
        compare_result();
        
        #50 run();
        compare_result();
        
        #50 run();
        compare_result();
        
        #50 run();
        compare_result();
        
        #50 run();
        compare_result();
        
        #50 run();
        compare_result();
        
        #50 run();
        compare_result();

        $finish;

    end

endmodule

