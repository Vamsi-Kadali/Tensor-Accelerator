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

    reg signed [WIDTH-1:0] a_lane [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b_lane [0:LANES-1][0:N_MAX-1];

    wire signed [ACC-1:0] res [0:LANES-1];

    reg [2:0] accel_op;
    reg scalar_en;
    reg [$clog2(N_MAX+1)-1:0] vec_len;

    integer i,j,k,lane;
    integer k_base;
    integer tile_len;

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
        .busy(),
        .done(accel_done)
    );

    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        START,
        RUN,
        ACCUM,
        NEXT_TILE,
        NEXT,
        FINISH
    } state_t;

    state_t state;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            accel_start <= 0;
            i <= 0;
            j <= 0;
            k_base <= 0;
            for (int r=0; r<M; r++)
                for (int c=0; c<N; c++)
                    C[r][c] <= 0;
        end
        else begin
            case(state)

            IDLE: begin
                done <= 0;
                accel_start <= 0;
                if(start) begin
                    i <= 0; j <= 0; k_base <= 0;
                    for (int r=0;r<M;r++)
                        for (int c=0;c<N;c++)
                            C[r][c] <= 0;
                    state <= LOAD;
                end
            end

            LOAD: begin
                // Determine tile length
                tile_len = (K_len - k_base > N_MAX) ? N_MAX : (K_len - k_base);
            
                case(op)
                    3'b000, 3'b100: begin // MAC / SUM
                        vec_len   <= tile_len;
                        scalar_en <= 0;
                        for(lane=0; lane<LANES; lane++)
                            for(k=0; k<tile_len; k++) begin
                                a_lane[lane][k] <= A[i][k_base + k];
                                if(j+lane < N_len)
                                    b_lane[lane][k] <= (op==3'b100) ? 1 : B[k_base + k][j+lane];
                            end
                    end
            
                    3'b001,3'b010: begin // ADD / SUB
                        vec_len   <= 1;
                        scalar_en <= 0;
                        for(lane=0; lane<LANES; lane++)
                            if(j+lane < N_len) begin
                                a_lane[lane][0] <= A[i][j+lane];
                                b_lane[lane][0] <= B[i][j+lane];
                            end
                    end
            
                    3'b011: begin // S_MULT
                        vec_len   <= 1;
                        scalar_en <= 1;
                        for(lane=0; lane<LANES; lane++)
                            if(j+lane < N_len) begin
                                a_lane[lane][0] <= A[i][j+lane];
                                b_lane[lane][0] <= scalar;
                            end
                    end
                endcase
            
                accel_op <= op;
                state <= START;
            end

            START: begin
                accel_start <= 1;
                state <= RUN;
            end

            RUN: begin
                accel_start <= 0;
                if(accel_done)
                    state <= ACCUM;
            end

            ACCUM: begin
                for(lane=0; lane<LANES; lane++)
                    if(j+lane < N_len) begin
                        case(op)
                            3'b000,3'b100: C[i][j+lane] <= C[i][j+lane] + res[lane]; // MAC/SUM
                            3'b001,3'b010,3'b011: C[i][j+lane] <= res[lane];          // ADD/SUB/S_MULT
                        endcase
                    end
                state <= NEXT_TILE;
            end

            NEXT_TILE: begin
                if((op==3'b000 || op==3'b100) && k_base + tile_len < K_len) begin
                    k_base <= k_base + tile_len;
                    state <= LOAD;
                end else begin
                    k_base <= 0;
                    state <= NEXT;
                end
            end

            NEXT: begin
                if(j + LANES < N_len) begin
                    j <= j + LANES;
                    state <= LOAD;
                end
                else if(i + 1 < M_len) begin
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