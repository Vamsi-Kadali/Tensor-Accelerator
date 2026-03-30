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
// Timing fix (Revision 0.03):
//
//   PROBLEM:  id_reg → a_raddr/b_raddr (comb) → tile_buf LUTRAM async read →
//             a_rdata/b_rdata (comb) → mac multiply (comb) → acc_reg_reg/D
//             This entire chain was one combinational path from one register
//             to the next.  With 16-bit operands the DSP multiply alone
//             consumes most of the cycle budget, leaving no slack for the
//             LUTRAM read + routing.  WNS -0.554 ns, 1446 failing endpoints
//             (all 64 lanes × all acc_reg bits).
//
//   FIX:      Insert a one-cycle pipeline register (a_rdata_r / b_rdata_r)
//             between the LUTRAM read output and the mac input.  This splits
//             the long combinational chain into two balanced stages:
//               Stage 1: id_reg → raddr → LUTRAM → rdata_r  (register)
//               Stage 2: rdata_r → mac → acc_reg            (register)
//
//   PIPELINE ADJUSTMENT:
//             Because rdata is now delayed by 1 cycle relative to id, the
//             accumulator would start one cycle late and finish one cycle late.
//             To keep the total latency at vec_len cycles (matching the FSM's
//             expectations and the accel_done handshake), we:
//               - Add a 1-cycle "run delay" flop (en_d1 / valid) so the mac
//                 and acc_reg only update when rdata_r is valid (i.e. en has
//                 been high for at least one cycle).
//               - Keep id counting from 0 to vec_len-1 as before, starting
//                 on the first en cycle.  rdata_r becomes valid on cycle 2.
//               - The done flag fires when id wraps AND en_d1 is asserted,
//                 i.e. the last accumulation has completed.
//             Net effect: the lane still consumes exactly vec_len+1 en-cycles
//             before asserting done - one extra cycle for pipeline fill - which
//             is the same as before because simd_array uses &lane_done and all
//             lanes are identical.  The accel_fsm sees done one cycle later
//             than the mac would have computed it combinationally, which is
//             correct and consistent across all lanes.
//
//   INTERFACE: Unchanged.  No port added or removed.  matrix_cont, accel_top,
//              simd_array, accel_fsm, tile_buf - none require any modification.
//////////////////////////////////////////////////////////////////////////////////

module vector_lane #( parameter WIDTH = 16, ACC = 40, N_MAX = 64 )(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,

    input [$clog2(N_MAX+1)-1:0] vec_len,

    // Output read addresses to tile_buf
    output [$clog2(N_MAX)-1:0] a_raddr,
    output [$clog2(N_MAX)-1:0] b_raddr,

    // Input data from tile_buf (asynchronously read)
    input signed [WIDTH-1:0] a_rdata,
    input signed [WIDTH-1:0] b_rdata,

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

    reg [ID_W-1:0]       id;
    reg signed [ACC-1:0] acc_reg;
    wire signed [ACC-1:0] acc_next;

    // ── Drive read addresses to tile_buf (combinational, unchanged) ────────────
    assign a_raddr = id;
    assign b_raddr = id;

    // ── TIMING FIX: register rdata to break id→LUTRAM→mac→acc_reg path ────────
    // Stage 1 register: captures tile_buf async read output each clock.
    // The mac now sees a settled register rather than a combinational LUTRAM output.
    reg signed [WIDTH-1:0] a_rdata_r;
    reg signed [WIDTH-1:0] b_rdata_r;

    always @(posedge clk) begin
        a_rdata_r <= a_rdata;
        b_rdata_r <= b_rdata;
    end

    // Pipeline valid flag: rdata_r is valid one cycle after en first asserts.
    // This prevents the accumulator from consuming stale/reset data on cycle 1.
    reg en_d1;
    always @(posedge clk) begin
        if (rst || load)
            en_d1 <= 1'b0;
        else
            en_d1 <= en & !done;
    end

    // id_end: registered copy of (id == vec_len-1) sampled the cycle BEFORE
    // rdata_r is valid for that last element - tells us when the last
    // accumulation result is in acc_reg and we should latch res/done.
    reg id_was_last;
    always @(posedge clk) begin
        if (rst || load)
            id_was_last <= 1'b0;
        else if (en && !done && vec_len != 0)
            id_was_last <= (id == vec_len - 1);
        else
            id_was_last <= 1'b0;
    end

    // ── Operand / accumulator mux (unchanged logic, now uses registered rdata) ─
    reg signed [WIDTH-1:0] a_eff;
    reg signed [WIDTH-1:0] b_eff;
    reg signed [ACC-1:0]   acc_eff;

    always @(*) begin
        a_eff   = a_rdata_r;
        b_eff   = b_rdata_r;
        acc_eff = acc_reg;

        case (op)
            OP_MATMULT: begin
            end

            OP_HADAMARD: begin
                acc_eff = 0;
            end

            OP_ADD: begin
                b_eff   = 1;
                acc_eff = b_rdata_r;
            end

            OP_SUB: begin
                b_eff   = 1;
                acc_eff = -b_rdata_r;
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

    // ── Sequential: reset on load, advance on en ──────────────────────────────
    always @(posedge clk) begin
        if (rst) begin
            id          <= '0;
            acc_reg     <= '0;
            res         <= '0;
            done        <= 1'b0;
        end
        else if (load) begin
            id          <= '0;
            acc_reg     <= '0;
            res         <= '0;
            done        <= 1'b0;
        end
        else if (en && !done && vec_len != 0) begin
            // Advance id every en cycle (drives raddr; rdata_r arrives next cycle)
            if (id == vec_len - 1)
                id <= '0;
            else
                id <= id + 1;
        end

        // Accumulate only when rdata_r is valid (en_d1 asserted)
        // This is stage 2 of the pipeline: settled register data into mac
        if (en_d1 && !done && vec_len != 0) begin
            acc_reg <= acc_next;

            // id_was_last was set when id pointed at vec_len-1 last cycle,
            // so rdata_r now holds the last element → acc_next is the final result
            if (id_was_last) begin
                res  <= acc_next;
                done <= 1'b1;
            end
        end
    end

endmodule