`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.03.2026 12:40:58
// Design Name: 
// Module Name: vector_lane
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
// Module Name: vector_lane
//
// Optimization: removed a_reg / b_reg internal copies.
//   Rationale: matrix_cont holds a_lane / b_lane stable throughout the entire
//   accel computation (it does not touch them until accel_done fires).  Reading
//   the inputs directly therefore gives identical functional behaviour while
//   saving 2 * N_MAX * WIDTH flip-flops per lane and eliminating the load clock
//   cycle that previously copied data into those registers.
//   The load pulse is still used to reset id / acc_reg / res / done so the
//   accel_fsm handshake is unchanged.
//////////////////////////////////////////////////////////////////////////////////

module vector_lane #( parameter WIDTH = 16, ACC = 40, N_MAX = 64 )(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,

    input [$clog2(N_MAX+1)-1:0] vec_len,

    input signed [WIDTH-1:0] a [0:N_MAX-1],
    input signed [WIDTH-1:0] b [0:N_MAX-1],

    output reg signed [ACC-1:0] res,
    output reg done
);

    localparam ID_W = (N_MAX <= 1) ? 1 : $clog2(N_MAX);

    localparam
        OP_MATMULT   = 3'b000,
        OP_ADD       = 3'b001,
        OP_SUB       = 3'b010,
        OP_HADAMARD  = 3'b011,
        OP_ROW_ACCUM = 3'b100,
        OP_COL_ACCUM = 3'b101;

    reg [ID_W-1:0]    id;
    reg signed [ACC-1:0] acc_reg;
    wire signed [ACC-1:0] acc_next;

    // ── Read directly from the input arrays (no local register copy) ──────────
    // a_lane / b_lane in matrix_cont are stable for the full computation window.
    wire signed [WIDTH-1:0] a_sel = a[id];
    wire signed [WIDTH-1:0] b_sel = b[id];

    // ── Operand / accumulator mux (unchanged) ─────────────────────────────────
    reg signed [WIDTH-1:0] a_eff;
    reg signed [WIDTH-1:0] b_eff;
    reg signed [ACC-1:0]   acc_eff;

    always @(*) begin
        a_eff   = a_sel;
        b_eff   = b_sel;
        acc_eff = acc_reg;

        case (op)
            OP_MATMULT: begin
            end

            OP_HADAMARD: begin
                acc_eff = 0;
            end

            OP_ADD: begin
                b_eff   = 1;
                acc_eff = b_sel;
            end

            OP_SUB: begin
                b_eff   = 1;
                acc_eff = -b_sel;
            end

            OP_ROW_ACCUM, OP_COL_ACCUM: begin
                b_eff = 1;
            end

            default: begin
                acc_eff = acc_reg;
            end
        endcase
    end

    mac #(WIDTH, ACC) mac_inst (
        .a      (a_eff),
        .b      (b_eff),
        .acc_in (acc_eff),
        .acc_out(acc_next)
    );

    // ── Sequential: reset control state on load, advance on en ───────────────
    always @(posedge clk) begin
        if (rst) begin
            id      <= '0;
            acc_reg <= '0;
            res     <= '0;
            done    <= 1'b0;
        end
        else if (load) begin
            // Reset counter and accumulator so the lane is ready to compute.
            // No data copy needed - inputs are read directly each cycle.
            id      <= '0;
            acc_reg <= '0;
            res     <= '0;
            done    <= 1'b0;
        end
        else if (en && !done && vec_len != 0) begin
            acc_reg <= acc_next;

            if (id == vec_len - 1) begin
                res  <= acc_next;
                done <= 1'b1;
                id   <= '0;
            end
            else begin
                id <= id + 1;
            end
        end
    end

endmodule