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

module tb_matrix_cont;

    parameter WIDTH   = 16;
    parameter ACC     = 40;
    parameter N_MAX   = 64;
    parameter LANES   = 64;
    parameter MAX_DIM = 256;
    
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
    wire done;
    
    matrix_cont #(WIDTH,N_MAX,LANES,MAX_DIM,ACC) DUT (
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
    
    integer i,j;
    
    task run;
    begin
        start = 1;
        #10 start = 0;
        wait(done);
        #10;
    end
    endtask
    
    
    initial begin
    
        clk=0;
        rst=1;
        start=0;
        
        #20 rst=0;
        
        //////////////////////////////////////////////////////
        // MATRIX MULTIPLY
        //////////////////////////////////////////////////////
        
        op = 3'b000;
        
        ////////////////////////////////
        // MIN (1x1)
        ////////////////////////////////
        
        M_len=1; K_len=1; N_len=1;
        
        A[0][0]=3;
        B[0][0]=4;
        
        run();
        
        $display("MM MIN C[0][0]=%0d",C[0][0]);
        
/*        
        ////////////////////////////////
        // MID (16x16)  
        // pattern = all ones
        ////////////////////////////////
        
        M_len=16; K_len=16; N_len=16;
        
        for(i=0;i<16;i=i+1)
        for(j=0;j<16;j=j+1) begin
        A[i][j]=1;
        B[i][j]=1;
        end
        
        run();
        
        $display("MM MID C[0][0]=%0d",C[0][0]);
        $display("MM MID C[15][15]=%0d",C[15][15]);
        
        
        ////////////////////////////////
        // MAX (256x256)
        // pattern = all ones
        ////////////////////////////////
        
        M_len=256; K_len=256; N_len=256;
        
        for(i=0;i<256;i=i+1)
        for(j=0;j<256;j=j+1) begin
        A[i][j]=1;
        B[i][j]=1;
        end
        
        run();
        
        $display("MM MAX C[0][0]=%0d",C[0][0]);
        $display("MM MAX C[255][255]=%0d",C[255][255]);
        
        */
        
        //////////////////////////////////////////////////////
        // MATRIX ADD
        //////////////////////////////////////////////////////
        
        op = 3'b001;
        
        ////////////////////////////////
        // MIN
        ////////////////////////////////
        
        M_len=1; N_len=1;
        
        A[0][0]=5;
        B[0][0]=7;
        
        run();
        
        $display("ADD MIN C[0][0]=%0d",C[0][0]);
        
        
        ////////////////////////////////
        // MID (16x16)
        // A=i , B=j
        ////////////////////////////////
        
        M_len=16; N_len=16;
        
        for(i=0;i<16;i=i+1)
        for(j=0;j<16;j=j+1) begin
        A[i][j]=i;
        B[i][j]=j;
        end
        
        run();
        
        $display("ADD MID C[0][15]=%0d",C[0][15]);
        $display("ADD MID C[15][15]=%0d",C[15][15]);
        
        
        ////////////////////////////////
        // MAX (256x256)
        // A=i , B=j
        ////////////////////////////////
        
        M_len=256; N_len=256;
        
        for(i=0;i<256;i=i+1)
        for(j=0;j<256;j=j+1) begin
        A[i][j]=i;
        B[i][j]=j;
        end
        
        run();
        
        $display("ADD MAX C[255][255]=%0d",C[255][255]);
        
        
        //////////////////////////////////////////////////////
        // MATRIX SUB
        //////////////////////////////////////////////////////
        
        op = 3'b010;
        
        ////////////////////////////////
        // MIN
        ////////////////////////////////
        
        M_len=1; N_len=1;
        
        A[0][0]=9;
        B[0][0]=3;
        
        run();
        
        $display("SUB MIN C[0][0]=%0d",C[0][0]);
        
        
        ////////////////////////////////
        // MID
        ////////////////////////////////
        
        M_len=16; N_len=16;
        
        for(i=0;i<16;i=i+1)
        for(j=0;j<16;j=j+1) begin
        A[i][j]=20+i;
        B[i][j]=j;
        end
        
        run();
        
        $display("SUB MID C[0][15]=%0d",C[0][15]);
        $display("SUB MID C[15][15]=%0d",C[15][15]);
        
        
        ////////////////////////////////
        // MAX
        ////////////////////////////////
        
        M_len=256; N_len=256;
        
        for(i=0;i<256;i=i+1)
        for(j=0;j<256;j=j+1) begin
        A[i][j]=100+i;
        B[i][j]=j;
        end
        
        run();
        
        $display("SUB MAX C[255][255]=%0d",C[255][255]);
        
        
        //////////////////////////////////////////////////////
        // SCALAR MULTIPLY
        //////////////////////////////////////////////////////
        
        op = 3'b011;
        scalar = 4;
        
        ////////////////////////////////
        // MIN
        ////////////////////////////////
        
        M_len=1; N_len=1;
        A[0][0]=5;
        
        run();
        
        $display("SCALAR MIN C[0][0]=%0d",C[0][0]);
        
        
        ////////////////////////////////
        // MID
        ////////////////////////////////
        
        M_len=16; N_len=16;
        
        for(i=0;i<16;i=i+1)
        for(j=0;j<16;j=j+1)
        A[i][j]=i+j;
        
        run();
        
        $display("SCALAR MID C[15][15]=%0d",C[15][15]);
        
        
        ////////////////////////////////
        // MAX
        ////////////////////////////////
        
        M_len=256; N_len=256;
        
        for(i=0;i<256;i=i+1)
        for(j=0;j<256;j=j+1)
        A[i][j]=i+j;
        
        run();
        
        $display("SCALAR MAX C[255][255]=%0d",C[255][255]);
        
        
        //////////////////////////////////////////////////////
        // ROW SUM
        //////////////////////////////////////////////////////
        
        op = 3'b100;
        
        ////////////////////////////////
        // MIN
        ////////////////////////////////
        
        M_len=1; K_len=1; N_len=1;
        A[0][0]=7;
        
        run();
        
        $display("SUM MIN Row0=%0d",C[0][0]);
        
        
        ////////////////////////////////
        // MID
        ////////////////////////////////
        
        M_len=16; K_len=16; N_len=1;
        
        for(i=0;i<16;i=i+1)
        for(j=0;j<16;j=j+1)
        A[i][j]=1;
        
        run();
        
        $display("SUM MID Row0=%0d",C[0][0]);
        
        
        ////////////////////////////////
        // MAX
        ////////////////////////////////
        
        M_len=256; K_len=256; N_len=1;
        
        for(i=0;i<256;i=i+1)
        for(j=0;j<256;j=j+1)
        A[i][j]=1;
        
        run();
        
        $display("SUM MAX Row0=%0d",C[0][0]);
        
        $finish;
    
    end

endmodule