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
    parameter MAX_DIM = 16, //64
    
    parameter N_MAX   = 16, //No of vectors per lane was 64
    parameter LANES   = 8, // was 64
    parameter TILE_R  = 2, // was 8
    parameter TILE_C  = 4, // was 8
    
    parameter ACC = 2*WIDTH + $clog2(MAX_DIM),
    parameter DEPTH   = MAX_DIM*MAX_DIM
)(
    input clk,
    input rst,
    input start,
    input [2:0] op,

    input [$clog2(MAX_DIM+1)-1:0] M_len,
    input [$clog2(MAX_DIM+1)-1:0] K_len,
    input [$clog2(MAX_DIM+1)-1:0] N_len,

    output reg done
);

    localparam ADDR_W = $clog2(DEPTH);

    // -----------------------------
    // BRAM INTERFACE
    // -----------------------------
    reg [ADDR_W-1:0] addr_a, addr_b, addr_c;

    wire signed [WIDTH-1:0] dout_a, dout_b;
    reg  signed [ACC-1:0]   din_c;
    reg we_c;

    tensor_bram #(WIDTH, DEPTH) bram_A (
        .clk(clk), .en(1'b1), .we(1'b0),
        .addr(addr_a), .din({WIDTH{1'b0}}), .dout(dout_a)
    );

    tensor_bram #(WIDTH, DEPTH) bram_B (
        .clk(clk), .en(1'b1), .we(1'b0),
        .addr(addr_b), .din({WIDTH{1'b0}}), .dout(dout_b)
    );

    tensor_bram #(ACC, DEPTH) bram_C (
        .clk(clk), .en(1'b1), .we(we_c),
        .addr(addr_c), .din(din_c), .dout()
    );

    // -----------------------------
    // LOCAL BUFFERS
    // -----------------------------
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

    // -----------------------------
    // LOAD CONTROL LOGIC
    // -----------------------------
    wire load_b_needed = (op == 3'b000) || (op == 3'b001) ||
                         (op == 3'b010) || (op == 3'b011);

    wire [$clog2(MAX_DIM+1)-1:0] a_rows = M_len;
    wire [$clog2(MAX_DIM+1)-1:0] a_cols =
        (op == 3'b000 || op == 3'b100) ? K_len : N_len;

    wire [$clog2(MAX_DIM+1)-1:0] b_rows =
        (op == 3'b000) ? K_len : M_len;

    wire [$clog2(MAX_DIM+1)-1:0] b_cols = N_len;

    integer i, j;

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
        STORE,
        DONE
    } state_t;

    state_t state;

    // -----------------------------
    // FSM
    // -----------------------------
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            matrix_start <= 0;
            we_c <= 0;
            i <= 0;
            j <= 0;
        end else begin
            case (state)

            //--------------------------------
            IDLE:
            //--------------------------------
            begin
                done <= 0;
                matrix_start <= 0;
                we_c <= 0;

                if (start) begin
                    i <= 0;
                    j <= 0;
                    state <= LOAD_A_ADDR;
                end
            end

            //--------------------------------
            // LOAD A
            //--------------------------------
            LOAD_A_ADDR: begin
                addr_a <= i * MAX_DIM + j;
                state <= LOAD_A_WAIT;
            end

            LOAD_A_WAIT: begin
                state <= LOAD_A_STORE;
            end

            LOAD_A_STORE: begin
                A_mat[i][j] <= dout_a;

                if (j + 1 < a_cols) begin
                    j <= j + 1;
                    state <= LOAD_A_ADDR;
                end else begin
                    j <= 0;
                    if (i + 1 < a_rows) begin
                        i <= i + 1;
                        state <= LOAD_A_ADDR;
                    end else begin
                        if (load_b_needed) begin
                            i <= 0;
                            j <= 0;
                            state <= LOAD_B_ADDR;
                        end else begin
                            state <= START;
                        end
                    end
                end
            end

            //--------------------------------
            // LOAD B
            //--------------------------------
            LOAD_B_ADDR: begin
                addr_b <= i * MAX_DIM + j;
                state <= LOAD_B_WAIT;
            end

            LOAD_B_WAIT: begin
                state <= LOAD_B_STORE;
            end

            LOAD_B_STORE: begin
                B_mat[i][j] <= dout_b;

                if (j + 1 < b_cols) begin
                    j <= j + 1;
                    state <= LOAD_B_ADDR;
                end else begin
                    j <= 0;
                    if (i + 1 < b_rows) begin
                        i <= i + 1;
                        state <= LOAD_B_ADDR;
                    end else begin
                        state <= START;
                    end
                end
            end

            //--------------------------------
            // START COMPUTE
            //--------------------------------
            START: begin
                matrix_start <= 1;
                state <= PAUSE;
            end

            PAUSE: begin
                matrix_start <= 0;
                if (matrix_done) begin
                    i <= 0;
                    j <= 0;
                    state <= STORE;
                end
            end

            //--------------------------------
            // STORE RESULT
            //--------------------------------
            STORE: begin
                we_c <= 1;
                addr_c <= i * MAX_DIM + j;
                din_c  <= C_mat[i][j];

                if (j + 1 < N_len) begin
                    j <= j + 1;
                end else begin
                    j <= 0;
                    if (i + 1 < M_len) begin
                        i <= i + 1;
                    end else begin
                        state <= DONE;
                    end
                end
            end

            //--------------------------------
            DONE:
            //--------------------------------
            begin
                we_c <= 0;
                done <= 1;
                state <= IDLE;
            end

            endcase
        end
    end

endmodule