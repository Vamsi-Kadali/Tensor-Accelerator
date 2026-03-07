`timescale 1ns / 1ps

module matrix_cont #(
    parameter WIDTH = 16,
    parameter ACC   = 32,
    parameter N_MAX = 8,
    parameter LANES = 4,
    parameter M = 4,
    parameter K = 8,
    parameter N = 4
)(
    input clk,
    input rst,
    input start,

    input [2:0] op,
    input signed [WIDTH-1:0] scalar,

    input [$clog2(M+1)-1:0] M_len,
    input [$clog2(K+1)-1:0] K_len,
    input [$clog2(N+1)-1:0] N_len,

    output reg signed [ACC-1:0] C [0:M-1][0:N-1],
    output reg done
);

 

    reg accel_start;
    wire accel_done;

    wire signed [ACC-1:0] res [0:LANES-1];

    reg [2:0] accel_op;
    reg scalar_en;
    reg [$clog2(N_MAX+1)-1:0] vec_len;


    integer i,j;

   

    accel_top #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) accel (
        .clk(clk),
        .rst(rst),
        .start(accel_start),
        .op(accel_op),
        .scalar_en(scalar_en),
        .vec_len(vec_len),
        .res(res),
        .busy(),
        .done(accel_done)
    );

    

    typedef enum logic [2:0] {
        IDLE,
        START,
        RUN,
        ACCUM,
        NEXT,
        FINISH
    } state_t;

    state_t state;

    integer lane;

    always @(posedge clk) begin

        if (rst) begin

            state <= IDLE;
            done <= 0;
            accel_start <= 0;

            i <= 0;
            j <= 0;

            for (int r=0;r<M;r++)
                for (int c=0;c<N;c++)
                    C[r][c] <= 0;

        end

        else begin

        case(state)

        

        IDLE: begin

            done <= 0;
            accel_start <= 0;

            if(start) begin

                for (int r=0;r<M;r++)
                    for (int c=0;c<N;c++)
                        C[r][c] <= 0;

                i <= 0;
                j <= 0;

                vec_len <= K_len;
                accel_op <= op;
                scalar_en <= 0;

                state <= START;

            end
        end

       

        START: begin
            accel_start <= 1;
            state <= RUN;
        end

       

        RUN: begin

            accel_start <= 0;

            if(accel_done)
                state <= ACCUM;

        end

        

        ACCUM: begin

            for(lane=0; lane<LANES; lane++)
                if(j+lane < N_len)
                    C[i][j+lane] <= C[i][j+lane] + res[lane];

            state <= NEXT;

        end

       

        NEXT: begin

            if(j + LANES < N_len) begin
                j <= j + LANES;
                state <= START;
            end
            else if(i + 1 < M_len) begin
                i <= i + 1;
                j <= 0;
                state <= START;
            end
            else begin
                state <= FINISH;
            end

        end

      

        FINISH: begin
            done <= 1;
            state <= IDLE;
        end

        endcase
        end
    end

endmodule
