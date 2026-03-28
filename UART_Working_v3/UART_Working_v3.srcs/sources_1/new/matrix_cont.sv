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


`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: matrix_cont
//
// Depth extension: added D_len port and d_base outer loop.
//
//   The BRAM address formula changes from:
//     row * MAX_DIM + col
//   to:
//     d * MAX_DIM * MAX_DIM + row * MAX_DIM + col
//
//   A new outermost loop over d (0 .. D_len-1) wraps the existing
//   tile-row / tile-col / k loops.  After FINISH the FSM now checks
//   whether more depth slices remain (NEXT_DEPTH) before asserting done.
//
//   For 2D operation pass D_len = 1; the d_base offset is then always 0
//   and behaviour is identical to the original design.
//
//   New FSM state added: NEXT_DEPTH (between FINISH and the existing done path).
//   State encoding grows from 4 bits (11 states) to 4 bits (12 states) - fits.
//
//   The C accumulator array is indexed as C[d][row][col] and is
//   MAX_DEPTH * MAX_DIM * MAX_DIM deep.  The outer dimension is the depth
//   slice currently being computed; partial results are held in C until
//   the entire tensor is processed, then tensor_top's STORE loop drains it.
//
//   All existing 2D behaviour is unchanged when D_len = 1.
//////////////////////////////////////////////////////////////////////////////////

module matrix_cont #(
    parameter WIDTH     = 16,
    parameter N_MAX     = 64,
    parameter LANES     = 64,
    parameter TILE_R    = 8,
    parameter TILE_C    = 8,
    parameter MAX_DIM   = 64,
    parameter MAX_DEPTH = 4,
    parameter ACC       = 2*WIDTH + $clog2(MAX_DIM),
    parameter ADDR_W    = $clog2(MAX_DEPTH * MAX_DIM * MAX_DIM)
)(
    input clk,
    input rst,
    input start,

    input [2:0] op,

    input [$clog2(MAX_DIM+1)-1:0]   M_len,
    input [$clog2(MAX_DIM+1)-1:0]   K_len,
    input [$clog2(MAX_DIM+1)-1:0]   N_len,
    input [$clog2(MAX_DEPTH+1)-1:0] D_len,

    // bram_A port-B read interface
    output reg [ADDR_W-1:0]       addr_a_out,
    input  signed [WIDTH-1:0]     dout_a_in,

    // bram_B port-B read interface
    output reg [ADDR_W-1:0]       addr_b_out,
    input  signed [WIDTH-1:0]     dout_b_in,

    output reg signed [ACC-1:0] C [0:MAX_DEPTH-1][0:MAX_DIM-1][0:MAX_DIM-1],
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

    integer load_k;
    integer load_lane;

    // depth loop counter
    integer d;          // current depth slice being computed
    integer d_base;     // flat BRAM offset for current slice = d * MAX_DIM * MAX_DIM

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
        LOAD_ADDR,
        LOAD_WAIT,
        LOAD_STORE,
        START,
        PAUSE,
        ACCUM,
        NEXT_K,
        NEXT_COL,
        NEXT_ROW,
        FINISH,
        NEXT_DEPTH   // new: advance to next depth slice or assert done
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
            state       <= IDLE;
            done        <= 0;
            accel_start <= 0;
            i           <= 0;
            j           <= 0;
            k_base      <= 0;
            d           <= 0;
            d_base      <= 0;
            load_k      <= 0;
            load_lane   <= 0;
            addr_a_out  <= '0;
            addr_b_out  <= '0;
        end
        else begin
            case (state)

            //--------------------------------
            IDLE:
            //--------------------------------
            begin
                done        <= 0;
                accel_start <= 0;

                if (start) begin
                    i      <= 0;
                    j      <= 0;
                    k_base <= 0;
                    d      <= 0;
                    d_base <= 0;

                    // clear entire C tensor
                    for (int dd = 0; dd < MAX_DEPTH; dd++)
                        for (int r = 0; r < MAX_DIM; r++)
                            for (int c = 0; c < MAX_DIM; c++)
                                C[dd][r][c] <= 0;

                    state <= LOAD_ADDR;
                end
            end

            //----------------------------------------------------------------
            // LOAD_ADDR / LOAD_WAIT / LOAD_STORE
            // Same as before but address formula includes d_base offset.
            //----------------------------------------------------------------

            LOAD_ADDR:
            begin
                if (load_k == 0 && load_lane == 0) begin
                    if (op == 3'b000 || op == 3'b100) begin
                        tile_len = (K_len - k_base > N_MAX) ? N_MAX : (K_len - k_base);
                        vec_len  <= tile_len;
                    end
                    else if (op == 3'b101) begin
                        tile_len = (M_len - k_base > N_MAX) ? N_MAX : (M_len - k_base);
                        vec_len  <= tile_len;
                    end
                    else begin
                        tile_len = 1;
                        vec_len  <= 1;
                    end
                end

                begin : addr_issue
                    int r_off, c_off;
                    lane_to_rc(load_lane, r_off, c_off);
                    row_idx = i + r_off;
                    col_idx = j + c_off;

                    if (op == 3'b000) begin
                        // MATMUL: A[d][row][k], B[d][k][col]
                        addr_a_out <= d_base + row_idx * MAX_DIM + (k_base + load_k);
                        addr_b_out <= d_base + (k_base + load_k) * MAX_DIM + col_idx;
                    end
                    else if (op == 3'b100) begin
                        // ROW_ACCUM: A[d][row][k]
                        addr_a_out <= d_base + row_idx * MAX_DIM + (k_base + load_k);
                        addr_b_out <= '0;
                    end
                    else if (op == 3'b101) begin
                        // COL_ACCUM: A[d][k][col]
                        addr_a_out <= d_base + (k_base + load_k) * MAX_DIM + col_idx;
                        addr_b_out <= '0;
                    end
                    else begin
                        // ADD/SUB/HADAMARD: A[d][row][col], B[d][row][col]
                        addr_a_out <= d_base + row_idx * MAX_DIM + col_idx;
                        addr_b_out <= d_base + row_idx * MAX_DIM + col_idx;
                    end
                end

                state <= LOAD_WAIT;
            end

            LOAD_WAIT:
            begin
                state <= LOAD_STORE;
            end

            LOAD_STORE:
            begin
                begin : store_sample
                    int r_off, c_off;
                    lane_to_rc(load_lane, r_off, c_off);
                    row_idx = i + r_off;
                    col_idx = j + c_off;

                    if (op == 3'b000) begin
                        if (load_k < tile_len && row_idx < M_len && col_idx < N_len) begin
                            a_lane[load_lane][load_k] <= dout_a_in;
                            b_lane[load_lane][load_k] <= dout_b_in;
                        end else begin
                            a_lane[load_lane][load_k] <= 0;
                            b_lane[load_lane][load_k] <= 0;
                        end
                    end
                    else if (op == 3'b100) begin
                        if (load_k < tile_len && row_idx < M_len && col_idx < N_len) begin
                            a_lane[load_lane][load_k] <= dout_a_in;
                            b_lane[load_lane][load_k] <= 1;
                        end else begin
                            a_lane[load_lane][load_k] <= 0;
                            b_lane[load_lane][load_k] <= 0;
                        end
                    end
                    else if (op == 3'b101) begin
                        if (load_k < tile_len && col_idx < N_len) begin
                            a_lane[load_lane][load_k] <= dout_a_in;
                            b_lane[load_lane][load_k] <= 1;
                        end else begin
                            a_lane[load_lane][load_k] <= 0;
                            b_lane[load_lane][load_k] <= 0;
                        end
                    end
                    else begin
                        if (row_idx < M_len && col_idx < N_len) begin
                            a_lane[load_lane][0] <= dout_a_in;
                            b_lane[load_lane][0] <= dout_b_in;
                        end else begin
                            a_lane[load_lane][0] <= 0;
                            b_lane[load_lane][0] <= 0;
                        end
                    end
                end

                if (load_lane + 1 < LANES) begin
                    load_lane <= load_lane + 1;
                    state     <= LOAD_ADDR;
                end
                else begin
                    load_lane <= 0;
                    if ((op == 3'b000 || op == 3'b100 || op == 3'b101) &&
                        (load_k + 1 < tile_len)) begin
                        load_k <= load_k + 1;
                        state  <= LOAD_ADDR;
                    end
                    else begin
                        load_k <= 0;
                        state  <= START;
                    end
                end
            end

            //--------------------------------
            START:
            //--------------------------------
            begin
                accel_start <= 1;
                state       <= PAUSE;
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
                            // accumulate into the current depth slice d
                            C[d][row_idx][col_idx] <= C[d][row_idx][col_idx] + res[lane];
                        else
                            C[d][row_idx][col_idx] <= res[lane];
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
                    state  <= LOAD_ADDR;
                end
                else if ((op == 3'b101) && (k_base + vec_len < M_len)) begin
                    k_base <= k_base + vec_len;
                    state  <= LOAD_ADDR;
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
                    j     <= j + TILE_C;
                    state <= LOAD_ADDR;
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
                    i     <= i + TILE_R;
                    j     <= 0;
                    state <= LOAD_ADDR;
                end
                else begin
                    state <= FINISH;
                end
            end

            //--------------------------------
            FINISH:
            //--------------------------------
            begin
                // Current depth slice d is done. Check if more slices remain.
                state <= NEXT_DEPTH;
            end

            //--------------------------------
            NEXT_DEPTH:
            //--------------------------------
            begin
                if (d + 1 < D_len) begin
                    // Advance to next depth slice, reset tile/k loops
                    d      <= d + 1;
                    d_base <= (d + 1) * MAX_DIM * MAX_DIM;
                    i      <= 0;
                    j      <= 0;
                    k_base <= 0;
                    state  <= LOAD_ADDR;
                end
                else begin
                    // All depth slices processed
                    done  <= 1;
                    state <= IDLE;
                end
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