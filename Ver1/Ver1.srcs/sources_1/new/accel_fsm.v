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
    input [1:0] op,
    input datapath_done,

    output reg en,
    output reg clear,
    output reg load,
    output reg done
);

    typedef enum logic [2:0] {
        IDLE  = 3'b000,
        INIT = 3'b001,
        LOAD  = 3'b010,
        RUN   = 3'b011,
        DONE  = 3'b100
    } state_t;

    state_t state, next_state;

    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        en    = 0;
        clear = 0;
        load = 0;
        done  = 0;
        next_state = state;

        case (state)
            IDLE: begin
                if (start)
                    next_state = INIT;
            end

            INIT: begin
                clear = 1;
                next_state = LOAD;
            end
            
            LOAD: begin
                load = 1;
                next_state = RUN;
            end
            
            RUN: begin
                en = 1;
                done = datapath_done;
                if (datapath_done)
                    next_state = DONE;
            end

            DONE: begin
                done = 0;
                if (start)
                    next_state = INIT;
                if (!start)
                    next_state = IDLE;
            end
            
        endcase
        
    end

endmodule