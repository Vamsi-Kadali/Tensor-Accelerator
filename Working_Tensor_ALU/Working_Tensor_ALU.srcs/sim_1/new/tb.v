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


module tb_tensor_top_random;

    parameter WIDTH   = 16;
    parameter ACC     = 40;
    parameter N_MAX   = 64;
    parameter LANES   = 64;
    parameter MAX_DIM = 64;
    parameter T_MAX   = 4;
    parameter TILE_R  = 8;
    parameter TILE_C  = 8;
    
    reg clk;
    reg rst;
    reg start;
    reg [2:0] op;
    reg signed [WIDTH-1:0] scalar;
    
    reg [$clog2(T_MAX+1)-1:0] T_len;
    reg [$clog2(MAX_DIM+1)-1:0] M_len;
    reg [$clog2(MAX_DIM+1)-1:0] K_len;
    reg [$clog2(MAX_DIM+1)-1:0] N_len;
    
    reg  signed [WIDTH-1:0] A [0:T_MAX-1][0:MAX_DIM-1][0:MAX_DIM-1];
    reg  signed [WIDTH-1:0] B [0:T_MAX-1][0:MAX_DIM-1][0:MAX_DIM-1];
    wire signed [ACC-1:0]  C [0:T_MAX-1][0:MAX_DIM-1][0:MAX_DIM-1];
    
    reg signed [ACC-1:0] GOLD [0:T_MAX-1][0:MAX_DIM-1][0:MAX_DIM-1];
    
    wire done;
    
    integer t,i,j,k;
    integer test;
    integer errors;
    
    //////////////////////////////////////////////////////////
    // DUT
    //////////////////////////////////////////////////////////
    
    tensor_top #(
        .WIDTH(WIDTH),
        .N_MAX(N_MAX),
        .LANES(LANES),
        .TILE_R(TILE_R),
        .TILE_C(TILE_C),
        .MAX_DIM(MAX_DIM),
        .T_MAX(T_MAX),
        .ACC(ACC)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .scalar(scalar),
        .T_len(T_len),
        .M_len(M_len),
        .K_len(K_len),
        .N_len(N_len),
        .A_tensor(A),
        .B_tensor(B),
        .C_tensor(C),
        .done(done)
    );
    
    always #5 clk = ~clk;
    
    //////////////////////////////////////////////////////////
    // INITIALIZE TENSORS
    //////////////////////////////////////////////////////////
    
    initial begin
        for(t=0;t<T_MAX;t=t+1)
            for(i=0;i<MAX_DIM;i=i+1)
                for(j=0;j<MAX_DIM;j=j+1)
                begin
                    A[t][i][j]    = 0;
                    B[t][i][j]    = 0;
                    GOLD[t][i][j] = 0;
                end
    end
    
    //////////////////////////////////////////////////////////
    // RUN
    //////////////////////////////////////////////////////////
    
    task run;
    begin
        @(posedge clk);
        start = 1;
    
        @(posedge clk);
        start = 0;
    
        wait(done);
        @(posedge clk);
    end
    endtask
    
    //////////////////////////////////////////////////////////
    // GOLDEN MODEL
    //////////////////////////////////////////////////////////
    
    task compute_golden;
    
    integer tt,m,n,kk;
    
    begin
        for(tt=0;tt<T_len;tt=tt+1)
            for(m=0;m<M_len;m=m+1)
                for(n=0;n<N_len;n=n+1)
                begin
    
                    GOLD[tt][m][n] = 0;
    
                    if(op==3'b000) begin
                        for(kk=0;kk<K_len;kk=kk+1)
                            GOLD[tt][m][n] =
                            GOLD[tt][m][n] + A[tt][m][kk]*B[tt][kk][n];
                    end
    
                    else if(op==3'b001)
                        GOLD[tt][m][n] = A[tt][m][n] + B[tt][m][n];
    
                    else if(op==3'b010)
                        GOLD[tt][m][n] = A[tt][m][n] - B[tt][m][n];
    
                    else if(op==3'b011)
                        GOLD[tt][m][n] = A[tt][m][n] * scalar;
                        
                    else if(op==3'b100) begin
                        for(kk=0;kk<K_len;kk=kk+1)
                            GOLD[tt][m][n] = GOLD[tt][m][n] + A[tt][m][kk];
                    end
    
                end
    end
    endtask
    
    //////////////////////////////////////////////////////////
    // COMPARE
    //////////////////////////////////////////////////////////
    
    task compare_result;
    
    integer tt,m,n;
    
    begin
        for(tt=0;tt<T_len;tt=tt+1)
            for(m=0;m<M_len;m=m+1)
                for(n=0;n<N_len;n=n+1)
                begin
    
                    if(C[tt][m][n] !== GOLD[tt][m][n]) begin
    
                        $display(
                        "ERROR TEST=%0d T=%0d (%0d,%0d) DUT=%0d GOLD=%0d",
                        test,tt,m,n,C[tt][m][n],GOLD[tt][m][n]);
    
                        errors = errors + 1;
                    end
    
                end
    end
    endtask
    
    //////////////////////////////////////////////////////////
    // RANDOMIZE MATRICES
    //////////////////////////////////////////////////////////
    
    task randomize_matrices;
    
    begin
    
    for(t=0;t<T_len;t=t+1)
    begin
    
        for(i=0;i<M_len;i=i+1)
            for(j=0;j<K_len;j=j+1)
                A[t][i][j] = $random;
    
        if(op==3'b000 || op==3'b100) begin
            // MATMUL
    
            for(i=0;i<K_len;i=i+1)
                for(j=0;j<N_len;j=j+1)
                    B[t][i][j] = $random;
        end
        else begin
            // ADD / SUB / SCALAR
    
            for(i=0;i<M_len;i=i+1)
                for(j=0;j<N_len;j=j+1)
                    B[t][i][j] = $random;
        end
    
    end
    
    end
    endtask
    
    //////////////////////////////////////////////////////////
    // MAIN TEST
    //////////////////////////////////////////////////////////
    
    initial begin
    
    clk = 0;
    rst = 1;
    start = 0;
    errors = 0;
    
    #20 rst = 0;
    
    for(test=0;test<100;test=test+1)
    begin
    
        //------------------------------------------------
        // RANDOM SIZES
        //------------------------------------------------
    
        T_len = $urandom_range(1,T_MAX);
    
        M_len = $urandom_range(1,10);
        K_len = $urandom_range(1,10);
        N_len = $urandom_range(1,10);
    
        //------------------------------------------------
        // RANDOM OPERATION
        //------------------------------------------------
    
        case($urandom_range(0,4))
    
            0: op = 3'b000; // MATMUL
            1: op = 3'b001; // ADD
            2: op = 3'b010; // SUB
            3: op = 3'b011; // SCALAR
            4: op = 3'b100;
    
        endcase
    
        scalar = $random;
    
        randomize_matrices();
    
        compute_golden();
    
        run();
    
        compare_result();
    
        $display("Test %0d complete (op=%b)",test,op);
    
    end
    
    //------------------------------------------------
    
    if(errors==0)
        $display("\nALL 100 RANDOM TENSOR TESTS PASSED\n");
    else
        $display("\nFAIL: %0d errors detected\n",errors);
    
    $finish;
    
    end

endmodule
