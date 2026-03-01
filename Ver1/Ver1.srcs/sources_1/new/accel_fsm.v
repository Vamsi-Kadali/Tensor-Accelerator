`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.02.2026 00:07:19
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


module accel_fsm (
    input clk,
    input rst,
    input start,
    input datapath_done,

    output reg en,
    output reg clear,
    output reg load,
    output reg busy,
    output reg done
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        INIT = 2'b01,
        RUN = 2'b10,
        DONE = 2'b11
    } state_t;

    state_t state, next_state;

    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        en = 1'b0;
        clear = 1'b0;
        load = 1'b0;
        busy = 1'b0;
        done = 1'b0;
        next_state = state;

        case (state)
            IDLE: begin //MAYBE ADD CLEAR HERE IN FUTURE
                busy = 1'b0;
                if (start)
                    next_state = INIT;
            end

            INIT: begin
                busy = 1'b1;
                load = 1'b1;
                next_state = RUN;
            end
            
            RUN: begin
                en = 1'b1;
                done = datapath_done;
                busy = 1'b1;
                if (datapath_done)
                    next_state = DONE;
            end

            DONE: begin
                busy = 1'b1;
                done = 1'b0;
                if (start)
                    next_state = INIT;
                if (!start)
                    next_state = IDLE;
            end
            
        endcase
        
    end

endmodule