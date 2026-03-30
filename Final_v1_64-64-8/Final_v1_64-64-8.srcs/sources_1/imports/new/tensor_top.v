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
// Module Name: tensor_top  (BRAM-IP revision)
//
// Changes vs previous version:
//
//   1. tensor_bram module instances replaced with Xilinx True Dual Port BRAM
//      IP instances (bram_A, bram_B, bram_C).  The IP is expected to be
//      configured as:
//        - True Dual Port
//        - Width / Depth matching WIDTH (or ACC for bram_C) and DEPTH
//        - Registered output (BRAM primitive output register disabled so
//          read latency = 1 cycle - matches the original tensor_bram behaviour)
//        - Write mode: Write First or No Change (either works; Read First
//          avoids needing separate logic but any mode is correct here)
//      Port-A pin names (Xilinx default): clka, wea, addra, dina, douta
//      Port-B pin names:                  clkb, web, addrb, dinb, doutb
//
//   2. The C_mat wire array [MAX_DEPTH][MAX_DIM][MAX_DIM] is removed.
//      matrix_cont now writes accumulation results directly into bram_C
//      via its bram_c_* port.  tensor_top no longer needs a STORE FSM.
//
//   3. The FSM is simplified to 4 states:
//        IDLE → START → PAUSE → DONE
//      The STORE_ARM / STORE_COMMIT states and their d_store / i / j
//      loop counters are gone.
//
//   4. bram_C port-A is now owned exclusively by matrix_cont (write/accum).
//      bram_C port-B remains the external read port (unchanged interface).
//
//   5. All external interfaces (we_a_ext, addr_a_ext, din_a_ext,
//      we_b_ext, addr_b_ext, din_b_ext, addr_c_ext, dout_c_ext) are
//      unchanged so uart_tensor_bridge needs no modification.
//
// IMPORTANT - Xilinx IP configuration notes:
//   bram_A / bram_B: WIDTH=16, DEPTH=DEPTH, both ports same clock
//   bram_C:          WIDTH=ACC, DEPTH=DEPTH, both ports same clock
//   All three should have output pipeline register = 0 (1-cycle read latency).
//
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
    input  [$clog2(MAX_DEPTH+1)-1:0] D_len,

    // External write port for A (port-A of bram_A)
    input  we_a_ext,
    input  [ADDR_W-1:0]       addr_a_ext,
    input  signed [WIDTH-1:0] din_a_ext,

    // External write port for B (port-A of bram_B)
    input  we_b_ext,
    input  [ADDR_W-1:0]       addr_b_ext,
    input  signed [WIDTH-1:0] din_b_ext,

    // External read port for C (port-B of bram_C)
    input  [ADDR_W-1:0]       addr_c_ext,
    output signed [ACC-1:0]   dout_c_ext,

    output reg done
);

    // ─────────────────────────────────────────────────────────────────────
    // bram_A wires
    //   Port-A: external host writes  (wea = we_a_ext)
    //   Port-B: matrix_cont reads     (web = 0, read-only)
    // ─────────────────────────────────────────────────────────────────────
    wire [ADDR_W-1:0]       addr_a_int;    // from matrix_cont
    wire signed [WIDTH-1:0] dout_a_int;    // to   matrix_cont

    bram_A u_bram_A (
        // Port A - host write
        .clka  (clk),
        .ena   (1'b1),
        .wea   (we_a_ext),
        .addra (addr_a_ext),
        .dina  (din_a_ext),
        .douta (),               // unused

        // Port B - matrix_cont read
        .clkb  (clk),
        .enb   (1'b1),
        .web   (1'b0),
        .addrb (addr_a_int),
        .dinb  ({WIDTH{1'b0}}),
        .doutb (dout_a_int)
    );

    // ─────────────────────────────────────────────────────────────────────
    // bram_B wires
    //   Port-A: external host writes
    //   Port-B: matrix_cont reads
    // ─────────────────────────────────────────────────────────────────────
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

    // ─────────────────────────────────────────────────────────────────────
    // bram_C wires
    //   Port-A: matrix_cont read/write (accumulation + clear)
    //   Port-B: external host reads
    // ─────────────────────────────────────────────────────────────────────
    wire [ADDR_W-1:0]     bram_c_addr;
    wire signed [ACC-1:0] bram_c_din;
    wire                  bram_c_we;
    wire signed [ACC-1:0] bram_c_dout_a;   // port-A read-back for accumulation

    bram_C u_bram_C (
        // Port A - matrix_cont read/write
        .clka  (clk),
        .ena   (1'b1),
        .wea   (bram_c_we),
        .addra (bram_c_addr),
        .dina  (bram_c_din),
        .douta (bram_c_dout_a),

        // Port B - host read
        .clkb  (clk),
        .enb   (1'b1),
        .web   (1'b0),
        .addrb (addr_c_ext),
        .dinb  ({ACC{1'b0}}),
        .doutb (dout_c_ext)
    );

    // ─────────────────────────────────────────────────────────────────────
    // matrix_cont instance
    // ─────────────────────────────────────────────────────────────────────
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
        // bram_A port-B
        .addr_a_out  (addr_a_int),
        .dout_a_in   (dout_a_int),
        // bram_B port-B
        .addr_b_out  (addr_b_int),
        .dout_b_in   (dout_b_int),
        // bram_C port-A (owned by matrix_cont)
        .bram_c_addr (bram_c_addr),
        .bram_c_din  (bram_c_din),
        .bram_c_we   (bram_c_we),
        .bram_c_dout (bram_c_dout_a),
        .done        (matrix_done)
    );

    // ─────────────────────────────────────────────────────────────────────
    // Simplified FSM - 4 states
    // STORE_ARM / STORE_COMMIT removed; matrix_cont writes bram_C directly.
    // done is asserted one cycle after matrix_done (DONE state).
    // ─────────────────────────────────────────────────────────────────────
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
            matrix_start <= 1'b0;   // default: deassert

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