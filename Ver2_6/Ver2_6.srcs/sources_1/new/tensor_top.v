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
    parameter MAX_DIM = 16,

    parameter N_MAX   = 16,
    parameter LANES   = 8,
    parameter TILE_R  = 2,
    parameter TILE_C  = 4,

    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM),
    parameter DEPTH   = MAX_DIM*MAX_DIM,
    parameter ADDR_W  = $clog2(DEPTH)
)(
    input  clk,
    input  rst,
    input  start,
    input  [2:0] op,

    input  [$clog2(MAX_DIM+1)-1:0] M_len,
    input  [$clog2(MAX_DIM+1)-1:0] K_len,
    input  [$clog2(MAX_DIM+1)-1:0] N_len,

    // External write port for A (port A of bram_A)
    input  we_a_ext,
    input  [ADDR_W-1:0]     addr_a_ext,
    input  signed [WIDTH-1:0] din_a_ext,

    // External write port for B (port A of bram_B)
    input  we_b_ext,
    input  [ADDR_W-1:0]     addr_b_ext,
    input  signed [WIDTH-1:0] din_b_ext,

    // External read port for C (port B of bram_C)
    input  [ADDR_W-1:0]       addr_c_ext,
    output signed [ACC-1:0]   dout_c_ext,

    output reg done
);

    // ──────────────────────────────────────────────
    // TRUE DUAL-PORT BRAM - Port A external, Port B internal
    // ──────────────────────────────────────────────

    // Internal DUT read addresses
    reg  [ADDR_W-1:0] addr_a_int, addr_b_int;

    // Internal DUT write signals for C
    reg  [ADDR_W-1:0]       addr_c_int;
    reg  signed [ACC-1:0]   din_c_int;
    reg  we_c_int;

    wire signed [WIDTH-1:0] dout_a_int;  // bram_A port B → DUT
    wire signed [WIDTH-1:0] dout_b_int;  // bram_B port B → DUT
    wire signed [ACC-1:0]   dout_c_ext_w; // bram_C port B → external

    // bram_A: port-A = ext write, port-B = DUT read
    tensor_bram #(.WIDTH(WIDTH), .DEPTH(DEPTH)) bram_A (
        .clk     (clk),
        // Port A - external writes
        .we_a    (we_a_ext),
        .addr_a  (addr_a_ext),
        .din_a   (din_a_ext),
        .dout_a  (),
        // Port B - DUT reads
        .we_b    (1'b0),
        .addr_b  (addr_a_int),
        .din_b   ({WIDTH{1'b0}}),
        .dout_b  (dout_a_int)
    );

    // bram_B: port-A = ext write, port-B = DUT read
    tensor_bram #(.WIDTH(WIDTH), .DEPTH(DEPTH)) bram_B (
        .clk     (clk),
        .we_a    (we_b_ext),
        .addr_a  (addr_b_ext),
        .din_a   (din_b_ext),
        .dout_a  (),
        .we_b    (1'b0),
        .addr_b  (addr_b_int),
        .din_b   ({WIDTH{1'b0}}),
        .dout_b  (dout_b_int)
    );

    // bram_C: port-A = DUT writes, port-B = external reads
    tensor_bram #(.WIDTH(ACC), .DEPTH(DEPTH)) bram_C (
        .clk     (clk),
        .we_a    (we_c_int),
        .addr_a  (addr_c_int),
        .din_a   (din_c_int),
        .dout_a  (),
        .we_b    (1'b0),
        .addr_b  (addr_c_ext),
        .din_b   ({ACC{1'b0}}),
        .dout_b  (dout_c_ext_w)
    );

    assign dout_c_ext = dout_c_ext_w;

    // ──────────────────────────────────────────────
    // LOCAL BUFFERS
    // ──────────────────────────────────────────────
    reg  signed [WIDTH-1:0] A_mat [0:MAX_DIM-1][0:MAX_DIM-1];
    reg  signed [WIDTH-1:0] B_mat [0:MAX_DIM-1][0:MAX_DIM-1];
    wire signed [ACC-1:0]   C_mat [0:MAX_DIM-1][0:MAX_DIM-1];

    reg  matrix_start;
    wire matrix_done;

    matrix_cont #(
        .WIDTH  (WIDTH),
        .N_MAX  (N_MAX),
        .LANES  (LANES),
        .TILE_R (TILE_R),
        .TILE_C (TILE_C),
        .MAX_DIM(MAX_DIM),
        .ACC    (ACC)
    ) matrix_engine (
        .clk    (clk),
        .rst    (rst),
        .start  (matrix_start),
        .op     (op),
        .M_len  (M_len),
        .K_len  (K_len),
        .N_len  (N_len),
        .A      (A_mat),
        .B      (B_mat),
        .C      (C_mat),
        .done   (matrix_done)
    );

    // ──────────────────────────────────────────────
    // DIMENSION HELPERS
    // ──────────────────────────────────────────────
    wire load_b_needed = (op == 3'b000) || (op == 3'b001) ||
                         (op == 3'b010) || (op == 3'b011);

    wire [$clog2(MAX_DIM+1)-1:0] a_rows = M_len;
    wire [$clog2(MAX_DIM+1)-1:0] a_cols =
        (op == 3'b000 || op == 3'b100) ? K_len : N_len;

    wire [$clog2(MAX_DIM+1)-1:0] b_rows =
        (op == 3'b000) ? K_len : M_len;
    wire [$clog2(MAX_DIM+1)-1:0] b_cols = N_len;

    integer i, j;

    // ──────────────────────────────────────────────
    // FSM
    // ──────────────────────────────────────────────
    typedef enum logic [3:0] {
        IDLE,
        LOAD_A_ADDR,
        LOAD_A_WAIT,
        LOAD_A_STORE,
        LOAD_B_ADDR,
        LOAD_B_WAIT,
        LOAD_B_STORE,
        START,
        PAUSE,
        STORE_SETUP,
        STORE_ARM,
        STORE_COMMIT,
        DONE
    } state_t;

    state_t state;

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            done         <= 0;
            matrix_start <= 0;
            we_c_int     <= 0;
            i <= 0;
            j <= 0;
        end else begin
            // Default: no BRAM-C write
            we_c_int <= 0;

            case (state)

            IDLE: begin
                done         <= 0;
                matrix_start <= 0;
                if (start) begin
                    i <= 0; j <= 0;
                    state <= LOAD_A_ADDR;
                end
            end

            // ── Load A from bram_A port-B ──────────────────
            LOAD_A_ADDR: begin
                addr_a_int <= i * MAX_DIM + j;
                state <= LOAD_A_WAIT;
            end

            LOAD_A_WAIT: state <= LOAD_A_STORE;

            LOAD_A_STORE: begin
                A_mat[i][j] <= dout_a_int;

                if (j + 1 < a_cols) begin
                    j <= j + 1; state <= LOAD_A_ADDR;
                end else begin
                    j <= 0;
                    if (i + 1 < a_rows) begin
                        i <= i + 1; state <= LOAD_A_ADDR;
                    end else begin
                        i <= 0; j <= 0;
                        state <= load_b_needed ? LOAD_B_ADDR : START;
                    end
                end
            end

            // ── Load B from bram_B port-B ──────────────────
            LOAD_B_ADDR: begin
                addr_b_int <= i * MAX_DIM + j;
                state <= LOAD_B_WAIT;
            end

            LOAD_B_WAIT: state <= LOAD_B_STORE;

            LOAD_B_STORE: begin
                B_mat[i][j] <= dout_b_int;

                if (j + 1 < b_cols) begin
                    j <= j + 1; state <= LOAD_B_ADDR;
                end else begin
                    j <= 0;
                    if (i + 1 < b_rows) begin
                        i <= i + 1; state <= LOAD_B_ADDR;
                    end else
                        state <= START;
                end
            end

            // ── Compute ────────────────────────────────────
            START: begin
                matrix_start <= 1;
                state <= PAUSE;
            end

            PAUSE: begin
                matrix_start <= 0;
                if (matrix_done) begin
                    i <= 0; j <= 0;
                    state <= STORE_SETUP;
                end
            end

            // ── Store C to bram_C port-A ───────────────────
            STORE_SETUP: begin
                we_c_int   <= 0;
                addr_c_int <= i * MAX_DIM + j;
                din_c_int  <= C_mat[i][j];
                state      <= STORE_ARM;
            end

            STORE_ARM: begin
                we_c_int <= 1;
                state    <= STORE_COMMIT;
            end

            STORE_COMMIT: begin
                we_c_int <= 0;

                if (j + 1 < N_len) begin
                    j <= j + 1; state <= STORE_SETUP;
                end else begin
                    j <= 0;
                    if (i + 1 < M_len) begin
                        i <= i + 1; state <= STORE_SETUP;
                    end else
                        state <= DONE;
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