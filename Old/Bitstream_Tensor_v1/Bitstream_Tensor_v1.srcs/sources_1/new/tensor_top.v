`timescale 1ns / 1ps

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
    input  [$clog2(MAX_DEPTH+1)-1:0] D_len,

    input  we_a_ext,
    input  [ADDR_W-1:0]       addr_a_ext,
    input  signed [WIDTH-1:0] din_a_ext,

    input  we_b_ext,
    input  [ADDR_W-1:0]       addr_b_ext,
    input  signed [WIDTH-1:0] din_b_ext,

    input  [ADDR_W-1:0]       addr_c_ext,
    output signed [ACC-1:0]   dout_c_ext,

    output reg done
    );

    wire [ADDR_W-1:0]       addr_a_int;
    wire signed [WIDTH-1:0] dout_a_int;

    bram_A u_bram_A (

    .clka  (clk),
    .ena   (1'b1),
    .wea   (we_a_ext),
    .addra (addr_a_ext),
    .dina  (din_a_ext),
    .douta (),

    .clkb  (clk),
    .enb   (1'b1),
    .web   (1'b0),
    .addrb (addr_a_int),
    .dinb  ({WIDTH{1'b0}}),
    .doutb (dout_a_int)
    );

    wire [ADDR_W-1:0]       addr_b_int;
    wire signed [WIDTH-1:0] dout_b_int;

    bram_B u_bram_B (
    .clka  (clk),
    .ena   (1'b1),
    .wea   (we_b_ext),
    .addra (addr_b_ext),
    .dina  (din_b_ext),
    .douta (),

    .clkb  (clk),
    .enb   (1'b1),
    .web   (1'b0),
    .addrb (addr_b_int),
    .dinb  ({WIDTH{1'b0}}),
    .doutb (dout_b_int)
    );

    wire [ADDR_W-1:0]     bram_c_addr;
    wire signed [ACC-1:0] bram_c_din;
    wire                  bram_c_we;
    wire signed [ACC-1:0] bram_c_dout_a;

    bram_C u_bram_C (

    .clka  (clk),
    .ena   (1'b1),
    .wea   (bram_c_we),
    .addra (bram_c_addr),
    .dina  (bram_c_din),
    .douta (bram_c_dout_a),

    .clkb  (clk),
    .enb   (1'b1),
    .web   (1'b0),
    .addrb (addr_c_ext),
    .dinb  ({ACC{1'b0}}),
    .doutb (dout_c_ext)
    );

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
    .clk         (clk),
    .rst         (rst),
    .start       (matrix_start),
    .op          (op),
    .M_len       (M_len),
    .K_len       (K_len),
    .N_len       (N_len),
    .D_len       (D_len),

    .addr_a_out  (addr_a_int),
    .dout_a_in   (dout_a_int),

    .addr_b_out  (addr_b_int),
    .dout_b_in   (dout_b_int),

    .bram_c_addr (bram_c_addr),
    .bram_c_din  (bram_c_din),
    .bram_c_we   (bram_c_we),
    .bram_c_dout (bram_c_dout_a),
    .done        (matrix_done)
    );

    typedef enum logic [1:0] {
    IDLE,
    START_ST,
    PAUSE_ST,
    DONE_ST
    } state_t;

    state_t state;

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            done         <= 1'b0;
            matrix_start <= 1'b0;
        end else begin
            matrix_start <= 1'b0;

            case (state)

            IDLE: begin
                done <= 1'b0;
                if (start) begin
                    state <= START_ST;
                end
            end

            START_ST: begin
                matrix_start <= 1'b1;
                state        <= PAUSE_ST;
            end

            PAUSE_ST: begin
                if (matrix_done)
                state <= DONE_ST;
            end

            DONE_ST: begin
                done  <= 1'b1;
                state <= IDLE;
            end

            default: state <= IDLE;

        endcase
    end
end

endmodule
