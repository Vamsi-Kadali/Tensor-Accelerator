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
    parameter WIDTH   = 16,
    parameter N_MAX   = 64,
    parameter LANES   = 6,
    parameter MAX_DIM = 256,
    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM)
)(
    input clk,
    input rst,
    input start,

    input [2:0] op,
    input signed [WIDTH-1:0] scalar,

    input [$clog2(MAX_DIM+1)-1:0] M_len,
    input [$clog2(MAX_DIM+1)-1:0] K_len,
    input [$clog2(MAX_DIM+1)-1:0] N_len,

    input  signed [WIDTH-1:0] A [0:MAX_DIM-1][0:MAX_DIM-1],
    input  signed [WIDTH-1:0] B [0:MAX_DIM-1][0:MAX_DIM-1],

    output reg signed [ACC-1:0] C [0:MAX_DIM-1][0:MAX_DIM-1],
    output reg done
);

    reg accel_start;
    wire accel_done;

    reg signed [WIDTH-1:0] a_lane [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b_lane [0:LANES-1][0:N_MAX-1];

    wire signed [ACC-1:0] res [0:LANES-1];

    reg scalar_en;
    reg [$clog2(N_MAX+1)-1:0] vec_len;

    integer i, j, k, lane;
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
        .op(op),
        .scalar_en(scalar_en),
        .vec_len(vec_len),
        .a(a_lane),
        .b(b_lane),
        .res(res),
        .busy(),
        .done(accel_done)
    );

    typedef enum logic [3:0] {
        IDLE,
        LOAD,
        START,
        PAUSE,
        ACCUM,
        NEXT_K,
        NEXT_COL,
        NEXT_ROW,
        FINISH
    } state_t;

    state_t state;

    always @(posedge clk) begin

        if (rst) begin
            state <= IDLE;
            done  <= 0;
            accel_start <= 0;

            i <= 0;
            j <= 0;
            k_base <= 0;

            for (int r = 0; r < MAX_DIM; r = r + 1) begin
                for (int c = 0; c < MAX_DIM; c = c + 1) begin
                    C[r][c] <= 0;
                end
            end
        end

        else begin
            case (state)

            //-----------------------------------
            IDLE:
            //-----------------------------------
            begin
                done <= 0;
                accel_start <= 0;

                if (start) begin
                    i <= 0;
                    j <= 0;
                    k_base <= 0;

                    for (int r = 0; r < MAX_DIM; r = r + 1) begin
                        for (int c = 0; c < MAX_DIM; c = c + 1) begin
                            C[r][c] <= 0;
                        end
                    end

                    state <= LOAD;
                end
            end

            //-----------------------------------
            LOAD:
            //-----------------------------------
            begin

                // MAC or SUM
                if (op == 3'b000 || op == 3'b100) begin

                    tile_len = (K_len - k_base > N_MAX) ?
                               N_MAX : (K_len - k_base);

                    vec_len   <= tile_len;
                    scalar_en <= 0;

                    for (lane = 0; lane < LANES; lane = lane + 1) begin
                        for (k = 0; k < N_MAX; k = k + 1) begin

                            a_lane[lane][k] <= 0;
                            b_lane[lane][k] <= 0;

                            if (k < tile_len && j + lane < N_len) begin
                                a_lane[lane][k] <= A[i][k_base + k];

                                if (op == 3'b100)
                                    b_lane[lane][k] <= 1;
                                else
                                    b_lane[lane][k] <= B[k_base + k][j + lane];
                            end
                        end
                    end
                end

                // ADD / SUB
                else if (op == 3'b001 || op == 3'b010) begin

                    vec_len   <= 1;
                    scalar_en <= 0;

                    for (lane = 0; lane < LANES; lane = lane + 1) begin

                        a_lane[lane][0] <= 0;
                        b_lane[lane][0] <= 0;

                        if (j + lane < N_len) begin
                            a_lane[lane][0] <= A[i][j + lane];
                            b_lane[lane][0] <= B[i][j + lane];
                        end
                    end
                end

                // SCALAR MULTIPLY
                else if (op == 3'b011) begin

                    vec_len   <= 1;
                    scalar_en <= 1;

                    for (lane = 0; lane < LANES; lane = lane + 1) begin

                        a_lane[lane][0] <= 0;
                        b_lane[lane][0] <= scalar;

                        if (j + lane < N_len) begin
                            a_lane[lane][0] <= A[i][j + lane];
                        end
                    end
                end

                state <= START;
            end

            //-----------------------------------
            START:
            //-----------------------------------
            begin
                accel_start <= 1;
                state <= PAUSE;
            end

            //-----------------------------------
            PAUSE:
            //-----------------------------------
            begin
                accel_start <= 0;

                if (accel_done)
                    state <= ACCUM;
            end

            //-----------------------------------
            ACCUM:
            //-----------------------------------
            begin
                for (lane = 0; lane < LANES; lane = lane + 1) begin
                    if (j + lane < N_len) begin

                        if (op == 3'b000 || op == 3'b100)
                            C[i][j + lane] <= C[i][j + lane] + res[lane];
                        else
                            C[i][j + lane] <= res[lane];

                    end
                end

                state <= NEXT_K;
            end

            //-----------------------------------
            NEXT_K:
            //-----------------------------------
            begin
                if ((op == 3'b000 || op == 3'b100) &&
                    k_base + vec_len < K_len) begin

                    k_base <= k_base + vec_len;
                    state  <= LOAD;

                end
                else begin
                    k_base <= 0;
                    state  <= NEXT_COL;
                end
            end

            //-----------------------------------
            NEXT_COL:
            //-----------------------------------
            begin
                if (j + LANES < N_len) begin
                    j <= j + LANES;
                    state <= LOAD;
                end
                else begin
                    state <= NEXT_ROW;
                end
            end

            //-----------------------------------
            NEXT_ROW:
            //-----------------------------------
            begin
                if (i + 1 < M_len) begin
                    i <= i + 1;
                    j <= 0;
                    state <= LOAD;
                end
                else begin
                    state <= FINISH;
                end
            end

            //-----------------------------------
            FINISH:
            //-----------------------------------
            begin
                done  <= 1;
                state <= IDLE;
            end

            endcase
        end
    end

endmodule


/*
    Balanced:       WIDTH   = 16
                    ACC     = 40
                    LANES   = 64
                    N_MAX   = 64
                    MAX_DIM = 256
                
    High Perf:      WIDTH   = 16
                    ACC     = 40
                    LANES   = 128
                    N_MAX   = 64
                    MAX_DIM = 256
                    
    Stress:         WIDTH   = 16
                    ACC     = 40
                    LANES   = 192
                    N_MAX   = 64
                    MAX_DIM = 256
*/