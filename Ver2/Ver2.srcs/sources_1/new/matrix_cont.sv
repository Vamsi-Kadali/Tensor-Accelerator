`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05.03.2026 20:40:45
// Design Name: 
// Module Name: matrix_cont
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

module matrix_cont #(
    parameter WIDTH = 16,
    parameter ACC   = 32,
    parameter N_MAX = 8,
    parameter LANES = 4,
    parameter M = 4,
    parameter K = 8,
    parameter N = 4
)(
    input clk,
    input rst,
    input start,

    input [2:0] op,
    input signed [WIDTH-1:0] scalar,

    input [$clog2(M+1)-1:0] M_len,
    input [$clog2(K+1)-1:0] K_len,
    input [$clog2(N+1)-1:0] N_len,

    input signed [WIDTH-1:0] A [0:M-1][0:K-1],
    input signed [WIDTH-1:0] B [0:K-1][0:N-1],

    output reg signed [ACC-1:0] C [0:M-1][0:N-1],
    output reg done
    );
    
    reg accel_start;
    wire accel_done;
    wire accel_busy;
    
    reg signed [WIDTH-1:0] a_lane [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b_lane [0:LANES-1][0:N_MAX-1];
    
    wire signed [ACC-1:0] res [0:LANES-1];
    
    reg [2:0] accel_op;
    reg scalar_en;
    reg [$clog2(N_MAX+1)-1:0] vec_len;
    
    accel_top #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) accel (
        .clk(clk),
        .rst(rst),
        .start(accel_start),
        .op(accel_op),
        .scalar_en(scalar_en),
        .vec_len(vec_len),
        .a(a_lane),
        .b(b_lane),
        .res(res),
        .busy(accel_busy),
        .done(accel_done)
    );
    
    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        START,
        RUN,
        STORE,
        NEXT,
        FINISH
    } state_t;
    
    localparam
        M_MULT = 3'b000,
        ADD    = 3'b001,
        SUB    = 3'b010,
        S_MULT = 3'b011;
    
    state_t state;
    
    integer i,j,k,lane;
    
    always @(posedge clk) begin
    
        if (rst) begin
            state <= IDLE;
            done <= 0;
            accel_start <= 0;
            i <= 0;
            j <= 0;
        
            for (int r = 0; r < M; r++)
                for (int c = 0; c < N; c++)
                    C[r][c] <= 0;
        end
        
        else begin
        
            case (state)
            
                IDLE: begin
                    done <= 0;
                    accel_start <= 0;
                
                    if (start) begin
                        for (int r = 0; r < M; r++)
                            for (int c = 0; c < N; c++)
                                C[r][c] <= 0;
                
                        i <= 0;
                        j <= 0;
                        state <= LOAD;
                    end
                end
                
                LOAD: begin
                
                    for (lane = 0; lane < LANES; lane++)
                        for (k = 0; k < N_MAX; k++) begin
                            a_lane[lane][k] <= 0;
                            b_lane[lane][k] <= 0;
                        end
                
                case (op)
                
                    M_MULT: begin
                        accel_op  <= 3'b000;
                        scalar_en <= 0;
                        vec_len   <= K_len;
                    
                        for (lane = 0; lane < LANES; lane++)
                            for (k = 0; k < N_MAX; k++) begin
                    
                                if (k < K_len)
                                    a_lane[lane][k] <= A[i][k];
                    
                                if (k < K_len && j + lane < N_len)
                                    b_lane[lane][k] <= B[k][j + lane];
                    
                            end
                    end
                    
                    ADD: begin
                        accel_op  <= 3'b001;
                        scalar_en <= 0;
                        vec_len   <= 1;
                    
                        for (lane = 0; lane < LANES; lane++) begin
                            if (j + lane < N_len) begin
                                a_lane[lane][0] <= A[i][j + lane];
                                b_lane[lane][0] <= B[i][j + lane];
                            end
                        end
                    end
                    
                    SUB: begin
                        accel_op  <= 3'b010;
                        scalar_en <= 0;
                        vec_len   <= 1;
                    
                        for (lane = 0; lane < LANES; lane++) begin
                            if (j + lane < N_len) begin
                                a_lane[lane][0] <= A[i][j + lane];
                                b_lane[lane][0] <= B[i][j + lane];
                            end
                        end
                    end
                    
                    S_MULT: begin
                        accel_op  <= 3'b011;
                        scalar_en <= 1;
                        vec_len   <= 1;
                    
                        for (lane = 0; lane < LANES; lane++) begin
                            if (j + lane < N_len) begin
                                a_lane[lane][0] <= A[i][j + lane];
                                b_lane[lane][0] <= scalar;
                            end
                        end
                    end
                    
                endcase
                
                state <= START;
                
                end
                
                START: begin
                    accel_start <= 1;
                    state <= RUN;
                end
                
                RUN: begin
                    accel_start <= 0;
                
                    if (accel_done)
                        state <= STORE;
                end
                
                STORE: begin
                
                    for (lane = 0; lane < LANES; lane++)
                        if (j + lane < N_len)
                            C[i][j + lane] <= res[lane];
                
                    state <= NEXT;
                
                end
                
                NEXT: begin
                
                    if (j + LANES < N_len) begin
                        j <= j + LANES;
                        state <= LOAD;
                    end
                
                    else if (i + 1 < M_len) begin
                        i <= i + 1;
                        j <= 0;
                        state <= LOAD;
                    end
                
                    else begin
                        state <= FINISH;
                    end
                
                end
                
                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
                
            endcase
        end
    end
    
endmodule