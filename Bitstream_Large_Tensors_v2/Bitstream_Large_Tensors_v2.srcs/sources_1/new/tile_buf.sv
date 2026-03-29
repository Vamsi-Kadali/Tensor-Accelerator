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
// Changes vs packed-bus revision:
//
//   DEPTH parameter now equals N_MAX (not LANES*N_MAX).
//   Each instance holds exactly one lane's k-slice.
//   LANES*2 instances are created in matrix_cont (one A, one B per lane).
//
//   Read port restored to original single async raddr/rdata port.
//   rdata_flat packed bus is removed entirely.
//
//   raddr is driven by lane_id[gl] from accel_top - a runtime signal
//   (vector_lane's id counter). This is the dynamic read address that
//   Vivado's LUTRAM inference template requires. With a static-index
//   generate loop as the read structure (previous revision), Vivado
//   saw DEPTH independent register reads and refused to infer RAM.
//   With a single dynamic raddr, inference is clean and unambiguous.
//
// Write port unchanged:
//   we        = tile_buf_we (asserted only in LOAD_STORE, one lane at a time)
//   waddr     = k_waddr_r   (registered load_k - settled plain register)
//   wdata     = tile_*_wdata muxed in matrix_cont
//
// Vivado LUTRAM inference checklist:
//   [x] Isolated always block - not buried in FSM
//   [x] waddr is a plain settled register (k_waddr_r)
//   [x] we is a simple 1-bit enable, one lane selected at a time
//   [x] Read is a single combinational assign with dynamic raddr
//       (raddr = lane_id[gl] from vector_lane's runtime id counter)
//////////////////////////////////////////////////////////////////////////////////

module tile_buf #(
    parameter WIDTH = 16,
    parameter DEPTH = 64        // N_MAX - one lane's k-slice only
)(
    input                           clk,

    // Write port - synchronous
    input                           we,
    input  [$clog2(DEPTH)-1:0]      waddr,
    input  signed [WIDTH-1:0]       wdata,

    // Read port - asynchronous, single element, dynamic address
    // raddr is driven by vector_lane's id counter via lane_id bus
    input  [$clog2(DEPTH)-1:0]      raddr,
    output signed [WIDTH-1:0]       rdata
);

    (* ram_style = "distributed" *) reg signed [WIDTH-1:0] mem [0:DEPTH-1];

    // Synchronous write
    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    // Asynchronous read - single dynamic address, zero latency
    // Matches Vivado distributed RAM inference template exactly
    assign rdata = mem[raddr];

endmodule