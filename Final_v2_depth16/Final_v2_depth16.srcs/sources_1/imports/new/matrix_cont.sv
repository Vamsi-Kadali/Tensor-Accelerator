`timescale 1ns / 1ps

module matrix_cont #(
    parameter WIDTH     = 16,
    parameter N_MAX     = 64,
    parameter LANES     = 16,
    parameter TILE_R    = 4,
    parameter TILE_C    = 4,
    parameter MAX_DIM   = 64,
    parameter MAX_DEPTH = 4,
    parameter ACC       = 2*WIDTH + $clog2(MAX_DIM),
    parameter ADDR_W    = $clog2(MAX_DEPTH * MAX_DIM * MAX_DIM)
)(
    input  clk,
    input  rst,
    input  start,

    input  [2:0] op,

    input  [$clog2(MAX_DIM+1)-1:0]   M_len,
    input  [$clog2(MAX_DIM+1)-1:0]   K_len,
    input  [$clog2(MAX_DIM+1)-1:0]   N_len,
    input  [$clog2(MAX_DEPTH+1)-1:0] D_len,

    output reg [ADDR_W-1:0]     addr_a_out,
    input  signed [WIDTH-1:0]   dout_a_in,

    output reg [ADDR_W-1:0]     addr_b_out,
    input  signed [WIDTH-1:0]   dout_b_in,

    output reg [ADDR_W-1:0]     bram_c_addr,
    output reg signed [ACC-1:0] bram_c_din,
    output reg                  bram_c_we,
    input  signed [ACC-1:0]     bram_c_dout,

    output reg done
);

    reg accel_start;
    wire accel_done;

    wire signed [ACC-1:0] res [0:LANES-1];

    reg [$clog2(N_MAX+1)-1:0] vec_len;

    reg [LANES-1:0]                    a_tile_we,    b_tile_we;
    reg [LANES-1:0][$clog2(N_MAX)-1:0] a_tile_waddr, b_tile_waddr;
    reg [LANES-1:0][WIDTH-1:0]          a_tile_wdata, b_tile_wdata;

    accel_top #(
        .WIDTH(WIDTH),
        .ACC  (ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) accel (
        .clk         (clk),
        .rst         (rst),
        .start       (accel_start),
        .op          (op),
        .vec_len     (vec_len),
        .a_tile_we   (a_tile_we),
        .a_tile_waddr(a_tile_waddr),
        .a_tile_wdata(a_tile_wdata),
        .b_tile_we   (b_tile_we),
        .b_tile_waddr(b_tile_waddr),
        .b_tile_wdata(b_tile_wdata),
        .res         (res),
        .busy        (),
        .done        (accel_done)
    );

    integer i, j, k_base, tile_len;
    integer load_k, load_lane;
    integer d, d_base;
    integer accum_lane;
    integer accum_row_r, accum_col_r;
    integer accum_row;
    integer accum_col;
    integer clear_addr;

    localparam integer TOTAL_DEPTH = MAX_DEPTH * MAX_DIM * MAX_DIM;

    typedef enum logic [3:0] {
        IDLE, CLEAR_C,
        LOAD_ADDR, LOAD_WAIT, LOAD_STORE,
        START, PAUSE,
        ACCUM_ADDR, ACCUM_WAIT, ACCUM_WRITE,
        NEXT_K, NEXT_COL, NEXT_ROW, FINISH, NEXT_DEPTH
    } state_t;

    state_t state;

    always @(*) begin
        a_tile_we    = '0;
        a_tile_waddr = '0;
        a_tile_wdata = '0;
        b_tile_we    = '0;
        b_tile_waddr = '0;
        b_tile_wdata = '0;

        if (state == LOAD_STORE) begin
            if (op == 3'b000) begin
                if (load_k < tile_len
                    && (i + load_lane/TILE_C) < M_len
                    && (j + load_lane%TILE_C) < N_len) begin
                    a_tile_we[load_lane]    = 1;
                    a_tile_waddr[load_lane] = load_k;
                    a_tile_wdata[load_lane] = dout_a_in;
                    b_tile_we[load_lane]    = 1;
                    b_tile_waddr[load_lane] = load_k;
                    b_tile_wdata[load_lane] = dout_b_in;
                end else begin
                    a_tile_we[load_lane]    = 1;
                    a_tile_waddr[load_lane] = load_k;
                    a_tile_wdata[load_lane] = '0;
                    b_tile_we[load_lane]    = 1;
                    b_tile_waddr[load_lane] = load_k;
                    b_tile_wdata[load_lane] = '0;
                end
            end
            else if (op == 3'b100) begin
                if (load_k < tile_len
                    && (i + load_lane/TILE_C) < M_len
                    && (j + load_lane%TILE_C) < N_len) begin
                    a_tile_we[load_lane]    = 1;
                    a_tile_waddr[load_lane] = load_k;
                    a_tile_wdata[load_lane] = dout_a_in;
                    b_tile_we[load_lane]    = 1;
                    b_tile_waddr[load_lane] = load_k;
                    b_tile_wdata[load_lane] = 1;
                end else begin
                    a_tile_we[load_lane]    = 1;
                    a_tile_waddr[load_lane] = load_k;
                    a_tile_wdata[load_lane] = '0;
                    b_tile_we[load_lane]    = 1;
                    b_tile_waddr[load_lane] = load_k;
                    b_tile_wdata[load_lane] = '0;
                end
            end
            else if (op == 3'b101) begin
                if (load_k < tile_len
                    && (j + load_lane%TILE_C) < N_len) begin
                    a_tile_we[load_lane]    = 1;
                    a_tile_waddr[load_lane] = load_k;
                    a_tile_wdata[load_lane] = dout_a_in;
                    b_tile_we[load_lane]    = 1;
                    b_tile_waddr[load_lane] = load_k;
                    b_tile_wdata[load_lane] = 1;
                end else begin
                    a_tile_we[load_lane]    = 1;
                    a_tile_waddr[load_lane] = load_k;
                    a_tile_wdata[load_lane] = '0;
                    b_tile_we[load_lane]    = 1;
                    b_tile_waddr[load_lane] = load_k;
                    b_tile_wdata[load_lane] = '0;
                end
            end
            else begin
                if ((i + load_lane/TILE_C) < M_len
                    && (j + load_lane%TILE_C) < N_len) begin
                    a_tile_we[load_lane]    = 1;
                    a_tile_waddr[load_lane] = 0;
                    a_tile_wdata[load_lane] = dout_a_in;
                    b_tile_we[load_lane]    = 1;
                    b_tile_waddr[load_lane] = 0;
                    b_tile_wdata[load_lane] = dout_b_in;
                end else begin
                    a_tile_we[load_lane]    = 1;
                    a_tile_waddr[load_lane] = 0;
                    a_tile_wdata[load_lane] = '0;
                    b_tile_we[load_lane]    = 1;
                    b_tile_waddr[load_lane] = 0;
                    b_tile_wdata[load_lane] = '0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            done        <= 0;
            accel_start <= 0;
            bram_c_we   <= 0;
            bram_c_addr <= '0;
            bram_c_din  <= '0;
            addr_a_out  <= '0;
            addr_b_out  <= '0;
            i           <= 0; j           <= 0;
            k_base      <= 0; tile_len    <= 1; vec_len <= 1;
            d           <= 0; d_base      <= 0;
            load_k      <= 0; load_lane   <= 0;
            accum_lane  <= 0;
            accum_row_r <= 0; accum_col_r <= 0;
            accum_row   <= 0; accum_col   <= 0;
            clear_addr  <= 0;
        end
        else begin
            bram_c_we <= 0;

            case (state)

                IDLE: begin
                    done        <= 0;
                    accel_start <= 0;
                    if (start) begin
                        i <= 0; j <= 0; k_base <= 0;
                        d <= 0; d_base <= 0;
                        clear_addr <= 0;
                        state <= CLEAR_C;
                    end
                end

                CLEAR_C: begin
                    bram_c_addr <= ADDR_W'(clear_addr);
                    bram_c_din  <= '0;
                    bram_c_we   <= 1;
                    if (clear_addr + 1 >= TOTAL_DEPTH) begin
                        clear_addr <= 0;
                        state      <= LOAD_ADDR;
                    end else
                        clear_addr <= clear_addr + 1;
                end

                LOAD_ADDR: begin
                    if (load_k == 0 && load_lane == 0) begin
                        if (op == 3'b000 || op == 3'b100) begin
                            tile_len <= (K_len - k_base > N_MAX) ? N_MAX : (K_len - k_base);
                            vec_len  <= (K_len - k_base > N_MAX) ? N_MAX : (K_len - k_base);
                        end else if (op == 3'b101) begin
                            tile_len <= (M_len - k_base > N_MAX) ? N_MAX : (M_len - k_base);
                            vec_len  <= (M_len - k_base > N_MAX) ? N_MAX : (M_len - k_base);
                        end else begin
                            tile_len <= 1;
                            vec_len  <= 1;
                        end
                    end

                    if (op == 3'b000) begin
                        addr_a_out <= ADDR_W'(d_base
                                      + (i + load_lane/TILE_C) * MAX_DIM
                                      + (k_base + load_k));
                        addr_b_out <= ADDR_W'(d_base
                                      + (k_base + load_k) * MAX_DIM
                                      + (j + load_lane%TILE_C));
                    end
                    else if (op == 3'b100) begin
                        addr_a_out <= ADDR_W'(d_base
                                      + (i + load_lane/TILE_C) * MAX_DIM
                                      + (k_base + load_k));
                        addr_b_out <= '0;
                    end
                    else if (op == 3'b101) begin
                        addr_a_out <= ADDR_W'(d_base
                                      + (k_base + load_k) * MAX_DIM
                                      + (j + load_lane%TILE_C));
                        addr_b_out <= '0;
                    end
                    else begin
                        addr_a_out <= ADDR_W'(d_base
                                      + (i + load_lane/TILE_C) * MAX_DIM
                                      + (j + load_lane%TILE_C));
                        addr_b_out <= ADDR_W'(d_base
                                      + (i + load_lane/TILE_C) * MAX_DIM
                                      + (j + load_lane%TILE_C));
                    end

                    state <= LOAD_WAIT;
                end

                LOAD_WAIT: state <= LOAD_STORE;

                LOAD_STORE: begin
                    if (load_lane + 1 < LANES) begin
                        load_lane <= load_lane + 1;
                        state     <= LOAD_ADDR;
                    end else begin
                        load_lane <= 0;
                        if ((op == 3'b000 || op == 3'b100 || op == 3'b101)
                            && (load_k + 1 < tile_len)) begin
                            load_k <= load_k + 1;
                            state  <= LOAD_ADDR;
                        end else begin
                            load_k <= 0;
                            state  <= START;
                        end
                    end
                end

                START: begin
                    accel_start <= 1;
                    state       <= PAUSE;
                end

                PAUSE: begin
                    accel_start <= 0;
                    if (accel_done) begin
                        accum_lane <= 0;
                        accum_row  <= i;
                        accum_col  <= j;
                        state      <= ACCUM_ADDR;
                    end
                end

                ACCUM_ADDR: begin
                    bram_c_addr <= ADDR_W'(d_base
                                   + accum_row * MAX_DIM
                                   + accum_col);
                    accum_row_r <= accum_row;
                    accum_col_r <= accum_col;
                    bram_c_we   <= 0;
                    state       <= ACCUM_WAIT;
                end

                ACCUM_WAIT: begin
                    state <= ACCUM_WRITE;
                end

                ACCUM_WRITE: begin
                    if (accum_row_r < M_len && accum_col_r < N_len) begin
                        bram_c_addr <= ADDR_W'(d_base
                                       + accum_row_r * MAX_DIM
                                       + accum_col_r);
                        bram_c_we   <= 1;
                        if (op == 3'b000 || op == 3'b100 || op == 3'b101)
                            bram_c_din <= bram_c_dout + res[accum_lane];
                        else
                            bram_c_din <= res[accum_lane];
                    end

                    if (accum_lane + 1 < LANES) begin
                        accum_lane <= accum_lane + 1;

                        if (accum_col - j + 1 < TILE_C) begin
                            accum_col <= accum_col + 1;
                        end else begin
                            accum_col <= j;
                            accum_row <= accum_row + 1;
                        end

                        state <= ACCUM_ADDR;
                    end else begin
                        accum_lane <= 0;
                        accum_row  <= 0;
                        accum_col  <= 0;
                        state      <= NEXT_K;
                    end
                end

                NEXT_K: begin
                    if ((op == 3'b000 || op == 3'b100) && (k_base + vec_len < K_len)) begin
                        k_base <= k_base + vec_len;
                        state  <= LOAD_ADDR;
                    end else if ((op == 3'b101) && (k_base + vec_len < M_len)) begin
                        k_base <= k_base + vec_len;
                        state  <= LOAD_ADDR;
                    end else begin
                        k_base <= 0;
                        state  <= NEXT_COL;
                    end
                end

                NEXT_COL: begin
                    if (j + TILE_C < N_len) begin
                        j     <= j + TILE_C;
                        state <= LOAD_ADDR;
                    end else begin
                        j     <= 0;
                        state <= NEXT_ROW;
                    end
                end

                NEXT_ROW: begin
                    if (i + TILE_R < M_len) begin
                        i     <= i + TILE_R;
                        j     <= 0;
                        state <= LOAD_ADDR;
                    end else begin
                        i     <= 0;
                        state <= FINISH;
                    end
                end

                FINISH: state <= NEXT_DEPTH;

                NEXT_DEPTH: begin
                    if (d + 1 < D_len) begin
                        d      <= d + 1;
                        d_base <= (d + 1) * MAX_DIM * MAX_DIM;
                        i      <= 0; j <= 0; k_base <= 0;
                        state  <= LOAD_ADDR;
                    end else begin
                        done  <= 1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule