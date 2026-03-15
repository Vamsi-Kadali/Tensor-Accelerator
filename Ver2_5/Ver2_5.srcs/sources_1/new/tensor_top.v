`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.03.2026 16:51:40
// Design Name: 
// Module Name: tensor_top
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


module tensor_top #(
    parameter WIDTH   = 16,
    parameter N_MAX   = 64,
    parameter LANES   = 64,
    parameter TILE_R  = 8,
    parameter TILE_C  = 8,
    parameter MAX_DIM = 64,
    parameter T_MAX   = 32,
    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM)
    )
    (
    input clk,
    input rst,
    input start,
    
    input [2:0] op,
    input signed [WIDTH-1:0] scalar,
    
    input [$clog2(T_MAX+1)-1:0]   T_len,
    input [$clog2(MAX_DIM+1)-1:0] M_len,
    input [$clog2(MAX_DIM+1)-1:0] K_len,
    input [$clog2(MAX_DIM+1)-1:0] N_len,
    
    input signed [WIDTH-1:0] A_tensor [0:T_MAX-1][0:MAX_DIM-1][0:MAX_DIM-1],
    input signed [WIDTH-1:0] B_tensor [0:T_MAX-1][0:MAX_DIM-1][0:MAX_DIM-1],
    
    output reg signed [ACC-1:0] C_tensor [0:T_MAX-1][0:MAX_DIM-1][0:MAX_DIM-1],
    output reg done
    );
    
    reg signed [WIDTH-1:0] A_mat [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B_mat [0:MAX_DIM-1][0:MAX_DIM-1];
    
    wire signed [ACC-1:0] C_mat [0:MAX_DIM-1][0:MAX_DIM-1];
    
    reg matrix_start;
    wire matrix_done;
    
    integer t;
    integer i,j,k;
    
    //////////////////////////////////////////////////////////
    // MATRIX ENGINE
    //////////////////////////////////////////////////////////
    
    matrix_cont #(
        .WIDTH(WIDTH),
        .N_MAX(N_MAX),
        .LANES(LANES),
        .TILE_R(TILE_R),
        .TILE_C(TILE_C),
        .MAX_DIM(MAX_DIM),
        .ACC(ACC)
    ) matrix_engine (
        .clk(clk),
        .rst(rst),
        .start(matrix_start),
        .op(op),
        .scalar(scalar),
        .M_len(M_len),
        .K_len(K_len),
        .N_len(N_len),
        .A(A_mat),
        .B(B_mat),
        .C(C_mat),
        .done(matrix_done)
    );
    
    //////////////////////////////////////////////////////////
    // FSM
    //////////////////////////////////////////////////////////
    
    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        START,
        PAUSE,
        STORE,
        NEXT,
        FINISH } state_t;
    
    state_t state;
    
    always @(posedge clk)
    begin
    
    if(rst)
    begin
        state <= IDLE;
        done <= 0;
        matrix_start <= 0;
        t <= 0;
    end
    
    else
    begin
    
    case(state)
    
    IDLE:
    begin
        done <= 0;
        matrix_start <= 0;
    
        if(start)
        begin
            t <= 0;
            state <= LOAD;
        end
    end
    
    
    LOAD:
    begin
    
        if(op==3'b000 || op==3'b100)
        begin
            // MATMUL
    
            for(i=0;i<M_len;i=i+1)
                for(k=0;k<K_len;k=k+1)
                    A_mat[i][k] <= A_tensor[t][i][k];
    
            for(k=0;k<K_len;k=k+1)
                for(j=0;j<N_len;j=j+1)
                    B_mat[k][j] <= B_tensor[t][k][j];
        end
        else
        begin
            // ADD / SUB / SCALAR
    
            for(i=0;i<M_len;i=i+1)
                for(j=0;j<N_len;j=j+1)
                begin
                    A_mat[i][j] <= A_tensor[t][i][j];
                    B_mat[i][j] <= B_tensor[t][i][j];
                end
        end
    
        state <= START;
    end
    
    
    START:
    begin
        matrix_start <= 1;
        state <= PAUSE;
    end
    
    
    PAUSE:
    begin
        matrix_start <= 0;
    
        if(matrix_done)
            state <= STORE;
    end
    
    
    STORE:
    begin
        for(i=0;i<M_len;i=i+1)
            for(j=0;j<N_len;j=j+1)
                C_tensor[t][i][j] <= C_mat[i][j];
    
        state <= NEXT;
    end
    
    
    NEXT:
    begin
        if(t+1 < T_len)
        begin
            t <= t + 1;
            state <= LOAD;
        end
        else
            state <= FINISH;
    end
    
    
    FINISH:
    begin
        done <= 1;
        state <= IDLE;
    end
    
    endcase
    
    end
    end

endmodule
