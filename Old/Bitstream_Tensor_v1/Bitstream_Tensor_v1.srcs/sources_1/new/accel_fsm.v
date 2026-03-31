`timescale 1ns / 1ps

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

    always @(posedge clk) begin
        if (rst)
        state <= IDLE;
        else
        state <= next_state;
    end

    always @(*) begin

        en         = 1'b0;
        load       = 1'b0;
        busy       = 1'b0;
        done       = 1'b0;
        next_state = state;

        case (state)

        IDLE: begin
            if (start) begin

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
