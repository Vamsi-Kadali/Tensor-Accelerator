`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.03.2026 13:47:53
// Design Name: 
// Module Name: tile_buf
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
// Module Name: tile_buf  (per-lane revision)
//
// Timing fix (Revision 0.02):
//
//   PROBLEM (Paths 1 & 2):
//     matrix_cont drives a_tile_waddr[lane] / b_tile_waddr[lane] with
//     the expression:
//         waddr = load_k   (an 'integer' FSM variable)
//     This is already a register, BUT in LOAD_ADDR the very same cycle that
//     i and j are being updated (carry chain propagating), those carry bits
//     fan out through the address adder into a_tile_waddr which becomes the
//     LUTRAM write address RAMA/I.  LUTRAM write ports have a tight setup
//     requirement.  The failing paths are:
//         i_reg[9]/C → TILE_BUFFERS_A[41].a_buf/mem_reg/RAMA/I   (-0.554 ns)
//         j_reg[5]/C → TILE_BUFFERS_B[40].b_buf/mem_reg/RAMA/I
//
//   FIX:
//     Register 'waddr' inside tile_buf by one additional pipeline stage.
//     The synchronous write now uses 'waddr_r' (the registered waddr) instead
//     of the raw waddr input.  This gives a full clock cycle of settling time
//     between the matrix_cont integer counter update and the LUTRAM write port.
//
//   FUNCTIONAL IMPACT:
//     The LUTRAM write is delayed by one cycle relative to 'we'.  This is
//     transparent because:
//       1. matrix_cont asserts 'we' only during LOAD_STORE, then transitions
//          to LOAD_ADDR (next lane) or START.  The tile_buf is never read
//          during LOAD_STORE or LOAD_ADDR - the simd_array only reads during
//          the RUN phase, which begins in START state (at least 2 cycles after
//          the last LOAD_STORE).  The one-cycle write latency is fully absorbed.
//       2. 'we' and 'wdata' are also registered here (delayed by the same
//          one cycle as waddr_r), so we/waddr/wdata all arrive at the LUTRAM
//          in the same registered cycle - the write is still atomic.
//
//   INTERFACE: Unchanged.  No port added or removed.
//              accel_top, matrix_cont, simd_array - no changes required.
//
// Original comments preserved below.
//
// Changes vs packed-bus revision:
//   DEPTH parameter now equals N_MAX (not LANES*N_MAX).
//   Each instance holds exactly one lane's k-slice.
//   LANES*2 instances are created in accel_top (one A, one B per lane).
//   Read port is single async raddr/rdata (dynamic address for LUTRAM inference).
//   Write port: synchronous, one lane at a time.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tile_buf #(
    parameter WIDTH = 16,
    parameter DEPTH = 64        // N_MAX - one lane's k-slice only
)(
    input                           clk,

    // Write port - synchronous (waddr pipelined internally for timing)
    input                           we,
    input  [$clog2(DEPTH)-1:0]      waddr,
    input  signed [WIDTH-1:0]       wdata,

    // Read port - asynchronous, single element, dynamic address
    input  [$clog2(DEPTH)-1:0]      raddr,
    output signed [WIDTH-1:0]       rdata
);

    (* ram_style = "distributed" *) reg signed [WIDTH-1:0] mem [0:DEPTH-1];

    // ── TIMING FIX: register we/waddr/wdata before LUTRAM write port ──────────
    // Breaks the path:  i_reg/j_reg (integer counter) → address adder →
    //                   a_tile_waddr/b_tile_waddr → waddr → LUTRAM RAMA/I
    // All three write-port signals are registered together so the write
    // remains atomic (we_r, waddr_r, wdata_r all change in the same cycle).
    reg                          we_r;
    reg [$clog2(DEPTH)-1:0]      waddr_r;
    reg signed [WIDTH-1:0]       wdata_r;

    always @(posedge clk) begin
        we_r    <= we;
        waddr_r <= waddr;
        wdata_r <= wdata;
    end

    // Synchronous write using registered signals
    always @(posedge clk) begin
        if (we_r)
            mem[waddr_r] <= wdata_r;
    end

    // Asynchronous read - single dynamic address, zero latency (unchanged)
    assign rdata = mem[raddr];

endmodule