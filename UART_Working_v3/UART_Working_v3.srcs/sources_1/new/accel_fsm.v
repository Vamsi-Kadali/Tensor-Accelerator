`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.03.2026 14:59:44
// Design Name: 
// Module Name: accel_fsm
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
// Module Name: accel_fsm
//
// Optimization: eliminated the INIT state.
//   Previously: IDLE → INIT (load=1 for one cycle) → RUN → DONE → IDLE
//   Now:        IDLE (load=1 on the same cycle start is sampled) → RUN → DONE → IDLE
//
//   The load pulse is now a Mealy output of IDLE: it fires combinationally
//   whenever start=1 while in IDLE, so the lane reset and the first en cycle
//   are now separated by exactly one clock instead of two.  The vector_lane
//   still sees a clean one-cycle load pulse followed by en on the next cycle -
//   the timing contract is identical from the lane's point of view.
//
//   State encoding shrinks from 2 bits (4 states) to 2 bits (3 states used),
//   saving one state worth of next-state logic.
//////////////////////////////////////////////////////////////////////////////////

module accel_fsm (
    input clk,
    input rst,
    input start,
    input datapath_done,

    output reg en,
    output reg load,
    output reg busy,
    output reg done
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        RUN  = 2'b01,
        DONE = 2'b10
    } state_t;

    state_t state, next_state;

    // ── State register ────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ── Next-state + output logic (Mealy) ────────────────────────────────────
    always @(*) begin
        // Defaults
        en         = 1'b0;
        load       = 1'b0;
        busy       = 1'b0;
        done       = 1'b0;
        next_state = state;

        case (state)

            IDLE: begin
                if (start) begin
                    // Assert load on the same cycle we detect start so the
                    // lane resets one cycle earlier than with the old INIT state.
                    load       = 1'b1;
                    busy       = 1'b1;
                    next_state = RUN;
                end
            end

            RUN: begin
                busy = 1'b1;
                en   = 1'b1;
                if (datapath_done)
                    next_state = DONE;
            end

            DONE: begin
                done       = 1'b1;
                next_state = IDLE;
            end

            default: next_state = IDLE;

        endcase
    end

endmodule
