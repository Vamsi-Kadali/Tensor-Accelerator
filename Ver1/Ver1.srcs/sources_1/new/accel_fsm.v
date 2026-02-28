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


module accel_fsm #( parameter N_W = 8 )(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [1:0] op,
    input  wire [N_W-1:0] N,
    input  wire datapath_done,

    output reg  en,
    output reg  clear,
    output reg  done
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        INIT = 2'b01,
        RUN  = 2'b10,
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
        en    = 0;
        clear = 0;
        done  = 0;
        next_state = state;

        case (state)
            IDLE: begin
                if (start)
                    next_state = INIT;
            end

            INIT: begin
                clear = 1;
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