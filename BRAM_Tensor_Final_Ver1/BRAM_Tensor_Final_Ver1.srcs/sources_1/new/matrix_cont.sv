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
    parameter LANES   = 64,
    parameter TILE_R  = 8,
    parameter TILE_C  = 8,
    parameter MAX_DIM = 64,
    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM)
)(
    input clk,
    input rst,
    input start,

    input [2:0] op,

    input [$clog2(MAX_DIM+1)-1:0] M_len,
    input [$clog2(MAX_DIM+1)-1:0] K_len,
    input [$clog2(MAX_DIM+1)-1:0] N_len,

    input  signed [WIDTH-1:0] A [0:MAX_DIM-1][0:MAX_DIM-1],
    input  signed [WIDTH-1:0] B [0:MAX_DIM-1][0:MAX_DIM-1],

    output reg signed [ACC-1:0] C [0:MAX_DIM-1][0:MAX_DIM-1],
    output reg done
);

    // --------------------------------
    // Internal Signals
    // --------------------------------
    reg accel_start;
    wire accel_done;

    reg signed [WIDTH-1:0] a_lane [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b_lane [0:LANES-1][0:N_MAX-1];

    wire signed [ACC-1:0] res [0:LANES-1];

    reg [$clog2(N_MAX+1)-1:0] vec_len;

    integer i, j, k, lane;
    integer k_base;
    integer tile_len;
    integer row_idx, col_idx;

    // --------------------------------
    // Accelerator
    // --------------------------------
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
        .vec_len(vec_len),
        .a(a_lane),
        .b(b_lane),
        .res(res),
        .busy(),
        .done(accel_done)
    );

    // --------------------------------
    // FSM
    // --------------------------------
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

    // lane → tile position
    function automatic void lane_to_rc(
        input int lane_idx,
        output int r_off,
        output int c_off
    );
        begin
            r_off = lane_idx / TILE_C;
            c_off = lane_idx % TILE_C;
        end
    endfunction

    // --------------------------------
    // FSM Logic
    // --------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done  <= 0;
            accel_start <= 0;

            i <= 0;
            j <= 0;
            k_base <= 0;
        end
        else begin
            case (state)

            //--------------------------------
            IDLE:
            //--------------------------------
            begin
                done <= 0;
                accel_start <= 0;

                if (start) begin
                    i <= 0;
                    j <= 0;
                    k_base <= 0;

                    // Clear output matrix
                    for (int r = 0; r < MAX_DIM; r++) begin
                        for (int c = 0; c < MAX_DIM; c++) begin
                            C[r][c] <= 0;
                        end
                    end

                    state <= LOAD;
                end
            end

            //--------------------------------
            LOAD:
            //--------------------------------
            begin
                if (op == 3'b000 || op == 3'b100) begin
                    // MATMUL / ROW_ACCUM
                    tile_len = (K_len - k_base > N_MAX) ? N_MAX : (K_len - k_base);
                    vec_len  <= tile_len;

                    for (lane = 0; lane < LANES; lane++) begin
                        int r_off, c_off;
                        lane_to_rc(lane, r_off, c_off);

                        row_idx = i + r_off;
                        col_idx = j + c_off;

                        for (k = 0; k < N_MAX; k++) begin
                            a_lane[lane][k] <= 0;
                            b_lane[lane][k] <= 0;

                            if (k < tile_len && row_idx < M_len && col_idx < N_len) begin
                                a_lane[lane][k] <= A[row_idx][k_base + k];

                                if (op == 3'b100)
                                    b_lane[lane][k] <= 1;
                                else
                                    b_lane[lane][k] <= B[k_base + k][col_idx];
                            end
                        end
                    end
                end

                else if (op == 3'b101) begin
                    // COLUMN ACCUM
                    tile_len = (M_len - k_base > N_MAX) ? N_MAX : (M_len - k_base);
                    vec_len  <= tile_len;

                    for (lane = 0; lane < LANES; lane++) begin
                        int r_off, c_off;
                        lane_to_rc(lane, r_off, c_off);

                        row_idx = i + r_off;
                        col_idx = j + c_off;

                        for (k = 0; k < N_MAX; k++) begin
                            a_lane[lane][k] <= 0;
                            b_lane[lane][k] <= 0;

                            if (k < tile_len && col_idx < N_len) begin
                                a_lane[lane][k] <= A[k_base + k][col_idx];
                                b_lane[lane][k] <= 1;
                            end
                        end
                    end
                end

                else begin
                    // ADD / SUB / HADAMARD
                    vec_len <= 1;

                    for (lane = 0; lane < LANES; lane++) begin
                        int r_off, c_off;
                        lane_to_rc(lane, r_off, c_off);

                        row_idx = i + r_off;
                        col_idx = j + c_off;

                        a_lane[lane][0] <= 0;
                        b_lane[lane][0] <= 0;

                        if (row_idx < M_len && col_idx < N_len) begin
                            a_lane[lane][0] <= A[row_idx][col_idx];
                            b_lane[lane][0] <= B[row_idx][col_idx];
                        end
                    end
                end

                state <= START;
            end

            //--------------------------------
            START:
            //--------------------------------
            begin
                accel_start <= 1;
                state <= PAUSE;
            end

            //--------------------------------
            PAUSE:
            //--------------------------------
            begin
                accel_start <= 0;
                if (accel_done)
                    state <= ACCUM;
            end

            //--------------------------------
            ACCUM:
            //--------------------------------
            begin
                for (lane = 0; lane < LANES; lane++) begin
                    int r_off, c_off;
                    lane_to_rc(lane, r_off, c_off);

                    row_idx = i + r_off;
                    col_idx = j + c_off;

                    if (row_idx < M_len && col_idx < N_len) begin
                        if (op == 3'b000 || op == 3'b100 || op == 3'b101)
                            C[row_idx][col_idx] <= C[row_idx][col_idx] + res[lane];
                        else
                            C[row_idx][col_idx] <= res[lane];
                    end
                end

                state <= NEXT_K;
            end

            //--------------------------------
            NEXT_K:
            //--------------------------------
            begin
                if ((op == 3'b000 || op == 3'b100) && (k_base + vec_len < K_len)) begin
                    k_base <= k_base + vec_len;
                    state  <= LOAD;
                end
                else if ((op == 3'b101) && (k_base + vec_len < M_len)) begin
                    k_base <= k_base + vec_len;
                    state  <= LOAD;
                end
                else begin
                    k_base <= 0;
                    state  <= NEXT_COL;
                end
            end

            //--------------------------------
            NEXT_COL:
            //--------------------------------
            begin
                if (j + TILE_C < N_len) begin
                    j <= j + TILE_C;
                    state <= LOAD;
                end
                else begin
                    state <= NEXT_ROW;
                end
            end

            //--------------------------------
            NEXT_ROW:
            //--------------------------------
            begin
                if (i + TILE_R < M_len) begin
                    i <= i + TILE_R;
                    j <= 0;
                    state <= LOAD;
                end
                else begin
                    state <= FINISH;
                end
            end

            //--------------------------------
            FINISH:
            //--------------------------------
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