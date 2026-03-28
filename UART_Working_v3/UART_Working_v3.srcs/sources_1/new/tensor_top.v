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


`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tensor_top
//
// Depth extension: added MAX_DEPTH parameter and D_len port.
//
//   DEPTH now equals MAX_DEPTH * MAX_DIM * MAX_DIM so each BRAM holds the
//   full tensor.  ADDR_W grows accordingly (e.g. 10 bits for 4x16x16=1024).
//
//   matrix_cont's C output is now indexed as C[d][row][col]; the STORE loop
//   gains an outer d-loop iterating over D_len slices.
//
//   For 2D-only use pass D_len = 1; behaviour is identical to the original.
//
//   tensor_top FSM is unchanged in structure (6 states); only the STORE_ARM /
//   STORE_COMMIT counters gain the depth dimension and the address formula
//   gains the d * MAX_DIM * MAX_DIM base offset.
//////////////////////////////////////////////////////////////////////////////////

module tensor_top #(
    parameter WIDTH     = 16,
    parameter MAX_DIM   = 16,
    parameter MAX_DEPTH = 4,

    parameter N_MAX     = 16,
    parameter LANES     = 8,
    parameter TILE_R    = 2,
    parameter TILE_C    = 4,

    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM),
    parameter DEPTH   = MAX_DEPTH * MAX_DIM * MAX_DIM,
    parameter ADDR_W  = $clog2(DEPTH)
)(
    input  clk,
    input  rst,
    input  start,
    input  [2:0] op,

    input  [$clog2(MAX_DIM+1)-1:0]   M_len,
    input  [$clog2(MAX_DIM+1)-1:0]   K_len,
    input  [$clog2(MAX_DIM+1)-1:0]   N_len,
    input  [$clog2(MAX_DEPTH+1)-1:0] D_len,   // number of depth slices (1 = 2D)

    // External write port for A (port A of bram_A)
    input  we_a_ext,
    input  [ADDR_W-1:0]       addr_a_ext,
    input  signed [WIDTH-1:0] din_a_ext,

    // External write port for B (port A of bram_B)
    input  we_b_ext,
    input  [ADDR_W-1:0]       addr_b_ext,
    input  signed [WIDTH-1:0] din_b_ext,

    // External read port for C (port B of bram_C)
    input  [ADDR_W-1:0]       addr_c_ext,
    output signed [ACC-1:0]   dout_c_ext,

    output reg done
);

    // ──────────────────────────────────────────────
    // BRAM wires
    // ──────────────────────────────────────────────
    wire [ADDR_W-1:0]       addr_a_int;
    wire signed [WIDTH-1:0] dout_a_int;

    wire [ADDR_W-1:0]       addr_b_int;
    wire signed [WIDTH-1:0] dout_b_int;

    reg  [ADDR_W-1:0]       addr_c_int;
    reg  signed [ACC-1:0]   din_c_int;
    reg  we_c_int;

    wire signed [ACC-1:0]   dout_c_ext_w;

    // bram_A: port-A = ext write, port-B = matrix_cont read
    tensor_bram #(.WIDTH(WIDTH), .DEPTH(DEPTH)) bram_A (
        .clk    (clk),
        .we_a   (we_a_ext),
        .addr_a (addr_a_ext),
        .din_a  (din_a_ext),
        .dout_a (),
        .we_b   (1'b0),
        .addr_b (addr_a_int),
        .din_b  ({WIDTH{1'b0}}),
        .dout_b (dout_a_int)
    );

    // bram_B: port-A = ext write, port-B = matrix_cont read
    tensor_bram #(.WIDTH(WIDTH), .DEPTH(DEPTH)) bram_B (
        .clk    (clk),
        .we_a   (we_b_ext),
        .addr_a (addr_b_ext),
        .din_a  (din_b_ext),
        .dout_a (),
        .we_b   (1'b0),
        .addr_b (addr_b_int),
        .din_b  ({WIDTH{1'b0}}),
        .dout_b (dout_b_int)
    );

    // bram_C: port-A = tensor_top FSM writes, port-B = external reads
    tensor_bram #(.WIDTH(ACC), .DEPTH(DEPTH)) bram_C (
        .clk    (clk),
        .we_a   (we_c_int),
        .addr_a (addr_c_int),
        .din_a  (din_c_int),
        .dout_a (),
        .we_b   (1'b0),
        .addr_b (addr_c_ext),
        .din_b  ({ACC{1'b0}}),
        .dout_b (dout_c_ext_w)
    );

    assign dout_c_ext = dout_c_ext_w;

    // ──────────────────────────────────────────────
    // matrix_cont
    // ──────────────────────────────────────────────
    // C is now [MAX_DEPTH][MAX_DIM][MAX_DIM]
    wire signed [ACC-1:0] C_mat [0:MAX_DEPTH-1][0:MAX_DIM-1][0:MAX_DIM-1];
    reg  matrix_start;
    wire matrix_done;

    matrix_cont #(
        .WIDTH    (WIDTH),
        .N_MAX    (N_MAX),
        .LANES    (LANES),
        .TILE_R   (TILE_R),
        .TILE_C   (TILE_C),
        .MAX_DIM  (MAX_DIM),
        .MAX_DEPTH(MAX_DEPTH),
        .ACC      (ACC)
    ) matrix_engine (
        .clk        (clk),
        .rst        (rst),
        .start      (matrix_start),
        .op         (op),
        .M_len      (M_len),
        .K_len      (K_len),
        .N_len      (N_len),
        .D_len      (D_len),
        // bram_A port-B
        .addr_a_out (addr_a_int),
        .dout_a_in  (dout_a_int),
        // bram_B port-B
        .addr_b_out (addr_b_int),
        .dout_b_in  (dout_b_int),
        .C          (C_mat),
        .done       (matrix_done)
    );

    // ──────────────────────────────────────────────
    // FSM - 6 states (unchanged structure)
    // STORE loop now iterates over d, i, j
    // ──────────────────────────────────────────────
    typedef enum logic [2:0] {
        IDLE,
        START,
        PAUSE,
        STORE_ARM,
        STORE_COMMIT,
        DONE
    } state_t;

    state_t state;
    integer i, j, d_store;   // d_store: depth index during STORE phase

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            done         <= 0;
            matrix_start <= 0;
            we_c_int     <= 0;
            i            <= 0;
            j            <= 0;
            d_store      <= 0;
        end else begin
            we_c_int <= 0;

            case (state)

            IDLE: begin
                done         <= 0;
                matrix_start <= 0;
                if (start) begin
                    i       <= 0;
                    j       <= 0;
                    d_store <= 0;
                    state   <= START;
                end
            end

            START: begin
                matrix_start <= 1;
                state        <= PAUSE;
            end

            PAUSE: begin
                matrix_start <= 0;
                if (matrix_done) begin
                    i       <= 0;
                    j       <= 0;
                    d_store <= 0;
                    state   <= STORE_ARM;
                end
            end

            // Address: d_store * MAX_DIM * MAX_DIM + i * MAX_DIM + j
            STORE_ARM: begin
                addr_c_int <= d_store * MAX_DIM * MAX_DIM + i * MAX_DIM + j;
                din_c_int  <= C_mat[d_store][i][j];
                we_c_int   <= 1;
                state      <= STORE_COMMIT;
            end

            STORE_COMMIT: begin
                if (j + 1 < N_len) begin
                    j     <= j + 1;
                    state <= STORE_ARM;
                end else begin
                    j <= 0;
                    if (i + 1 < M_len) begin
                        i     <= i + 1;
                        state <= STORE_ARM;
                    end else begin
                        i <= 0;
                        // current depth slice stored, advance to next
                        if (d_store + 1 < D_len) begin
                            d_store <= d_store + 1;
                            state   <= STORE_ARM;
                        end else
                            state <= DONE;
                    end
                end
            end

            DONE: begin
                done  <= 1;
                state <= IDLE;
            end

            endcase
        end
    end

endmodule