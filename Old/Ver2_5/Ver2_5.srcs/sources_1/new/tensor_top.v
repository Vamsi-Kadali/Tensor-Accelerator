`timescale 1ns / 1ps

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
    input clk,
    input rst,
    input start,
    input [2:0] op,

    input [$clog2(MAX_DIM+1)-1:0] M_len,
    input [$clog2(MAX_DIM+1)-1:0] K_len,
    input [$clog2(MAX_DIM+1)-1:0] N_len,

    input we_a_ext,
    input we_b_ext,
    input [ADDR_W-1:0] addr_a_ext,
    input [ADDR_W-1:0] addr_b_ext,
    input signed [WIDTH-1:0] din_a_ext,
    input signed [WIDTH-1:0] din_b_ext,

    input [ADDR_W-1:0] addr_c_ext,
    output signed [ACC-1:0] dout_c_ext,

    output reg done
    );

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

    reg use_internal_bram;

    reg  [ADDR_W-1:0] addr_a, addr_b, addr_c;
    wire signed [WIDTH-1:0] dout_a, dout_b;
    wire signed [ACC-1:0]   dout_c_int;
    reg  signed [ACC-1:0]   din_c;
    reg we_c;

    wire compute_mode = use_internal_bram;

    tensor_bram #(WIDTH, DEPTH) bram_A (
    .clk(clk),
    .en(1'b1),
    .we(compute_mode ? 1'b0 : we_a_ext),
    .addr(compute_mode ? addr_a : addr_a_ext),
    .din(din_a_ext),
    .dout(dout_a)
    );

    tensor_bram #(WIDTH, DEPTH) bram_B (
    .clk(clk),
    .en(1'b1),
    .we(compute_mode ? 1'b0 : we_b_ext),
    .addr(compute_mode ? addr_b : addr_b_ext),
    .din(din_b_ext),
    .dout(dout_b)
    );

    tensor_bram #(ACC, DEPTH) bram_C (
    .clk(clk),
    .en(1'b1),
    .we(compute_mode ? we_c : 1'b0),
    .addr(compute_mode ? addr_c : addr_c_ext),
    .din(din_c),
    .dout(dout_c_int)
    );

    assign dout_c_ext = dout_c_int;

    reg  signed [WIDTH-1:0] A_mat [0:MAX_DIM-1][0:MAX_DIM-1];
    reg  signed [WIDTH-1:0] B_mat [0:MAX_DIM-1][0:MAX_DIM-1];
    wire signed [ACC-1:0]   C_mat [0:MAX_DIM-1][0:MAX_DIM-1];

    reg matrix_start;
    wire matrix_done;

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
    .M_len(M_len),
    .K_len(K_len),
    .N_len(N_len),
    .A(A_mat),
    .B(B_mat),
    .C(C_mat),
    .done(matrix_done)
    );

    wire load_b_needed = (op == 3'b000) || (op == 3'b001) ||
    (op == 3'b010) || (op == 3'b011);

    wire [$clog2(MAX_DIM+1)-1:0] a_rows = M_len;
    wire [$clog2(MAX_DIM+1)-1:0] a_cols =
    (op == 3'b000 || op == 3'b100) ? K_len : N_len;

    wire [$clog2(MAX_DIM+1)-1:0] b_rows =
    (op == 3'b000) ? K_len : M_len;

    wire [$clog2(MAX_DIM+1)-1:0] b_cols = N_len;

    integer i, j;
    integer r, c;

    always @(posedge clk) begin
        if (rst) begin
            state             <= IDLE;
            use_internal_bram <= 1'b0;
            done              <= 1'b0;
            matrix_start      <= 1'b0;
            we_c              <= 1'b0;
            addr_a            <= '0;
            addr_b            <= '0;
            addr_c            <= '0;
            din_c             <= '0;
            i                 <= 0;
            j                 <= 0;

            for (r = 0; r < MAX_DIM; r = r + 1) begin
                for (c = 0; c < MAX_DIM; c = c + 1) begin
                    A_mat[r][c] <= '0;
                    B_mat[r][c] <= '0;
                end
            end
        end
        else begin
            case (state)

            IDLE: begin
                done         <= 1'b0;
                matrix_start <= 1'b0;
                we_c         <= 1'b0;
                use_internal_bram <= 1'b0;

                if (start) begin
                    use_internal_bram <= 1'b1;
                    i     <= 0;
                    j     <= 0;
                    state <= LOAD_A_ADDR;
                end
            end

            LOAD_A_ADDR: begin
                addr_a <= i * MAX_DIM + j;
                state  <= LOAD_A_WAIT;
            end

            LOAD_A_WAIT: begin
                state <= LOAD_A_STORE;
            end

            LOAD_A_STORE: begin
                A_mat[i][j] <= dout_a;

                if (j + 1 < a_cols) begin
                    j     <= j + 1;
                    state <= LOAD_A_ADDR;
                end
                else begin
                    j <= 0;
                    if (i + 1 < a_rows) begin
                        i     <= i + 1;
                        state <= LOAD_A_ADDR;
                    end
                    else begin
                        if (load_b_needed) begin
                            i     <= 0;
                            j     <= 0;
                            state <= LOAD_B_ADDR;
                        end
                        else begin
                            state <= START;
                        end
                    end
                end
            end

            LOAD_B_ADDR: begin
                addr_b <= i * MAX_DIM + j;
                state  <= LOAD_B_WAIT;
            end

            LOAD_B_WAIT: begin
                state <= LOAD_B_STORE;
            end

            LOAD_B_STORE: begin
                B_mat[i][j] <= dout_b;

                if (j + 1 < b_cols) begin
                    j     <= j + 1;
                    state <= LOAD_B_ADDR;
                end
                else begin
                    j <= 0;
                    if (i + 1 < b_rows) begin
                        i     <= i + 1;
                        state <= LOAD_B_ADDR;
                    end
                    else begin
                        state <= START;
                    end
                end
            end

            START: begin
                matrix_start <= 1'b1;
                state        <= PAUSE;
            end

            PAUSE: begin
                matrix_start <= 1'b0;
                if (matrix_done) begin
                    i     <= 0;
                    j     <= 0;
                    state <= STORE_SETUP;
                end
            end

            STORE_SETUP: begin
                we_c   <= 1'b0;
                addr_c <= i * MAX_DIM + j;
                state  <= STORE_ARM;
            end

            STORE_ARM: begin
                din_c  <= C_mat[i][j];
                we_c  <= 1'b1;
                state <= STORE_COMMIT;
            end

            STORE_COMMIT: begin
                we_c <= 1'b0;

                if (j + 1 < N_len) begin
                    j     <= j + 1;
                    state <= STORE_SETUP;
                end
                else begin
                    j <= 0;
                    if (i + 1 < M_len) begin
                        i     <= i + 1;
                        state <= STORE_SETUP;
                    end
                    else begin
                        state <= DONE;
                    end
                end
            end

            DONE: begin
                we_c <= 1'b0;
                done <= 1'b1;
                use_internal_bram <= 1'b0;
                state <= IDLE;
            end

        endcase
    end
end

endmodule
