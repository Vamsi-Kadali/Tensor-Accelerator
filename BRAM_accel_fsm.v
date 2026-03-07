`timescale 1ns / 1ps

module accel_fsm (
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic datapath_done,

    output logic en,
    output logic load,
    output logic busy,
    output logic done
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        INIT = 2'b01,
        RUN  = 2'b10,
        FIN  = 2'b11
    } state_t;

    state_t state, next_state;

        always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

  
    always_comb begin

        en   = 1'b0;
        load = 1'b0;
        busy = 1'b0;
        done = 1'b0;

        next_state = state;

        case (state)

            
            IDLE: begin
                if (start)
                    next_state = INIT;
            end

            
            INIT: begin
                busy = 1'b1;
                load = 1'b1;   // reset addr counter
                next_state = RUN;
            end

           
            RUN: begin
                busy = 1'b1;
                en   = 1'b1;

                if (datapath_done)
                    next_state = FIN;
            end

           
            FIN: begin
                done = 1'b1;
                next_state = IDLE;
            end

        endcase
    end

endmodule
