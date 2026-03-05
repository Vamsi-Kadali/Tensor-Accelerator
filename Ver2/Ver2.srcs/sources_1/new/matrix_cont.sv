`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05.03.2026 20:40:45
// Design Name: 
// Module Name: matrix_cont
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

module matrix_cont #( parameter WIDTH = 16, ACC = 32, N_MAX = 8, LANES = 4, M = 4, K = 8, N = 4 )(
    input clk,
    input rst,
    input start,

    input signed [WIDTH-1:0] A [0:M-1][0:K-1],
    input signed [WIDTH-1:0] B [0:K-1][0:N-1],

    output reg signed [ACC-1:0] C [0:M-1][0:N-1],
    output reg done
);

    reg accel_start;
    wire accel_busy;
    wire accel_done;

    reg signed [WIDTH-1:0] a_lane [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b_lane [0:LANES-1][0:N_MAX-1];

    wire signed [ACC-1:0] res [0:LANES-1];

    accel_top #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) accel (
        .clk(clk),
        .rst(rst),
        .start(accel_start),
        .op(3'b000),
        .scalar_en(1'b0),
        .vec_len(K[$clog2(N_MAX+1)-1:0]),
        .a(a_lane),
        .b(b_lane),
        .res(res),
        .busy(accel_busy),
        .done(accel_done)
    );

    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        START,
        RUN,
        STORE,
        NEXT,
        FINISH
    } state_t;

    state_t state;

    integer i, j, r, s;
    integer k;
    integer lane;

    always @(posedge clk) begin

        if (rst) begin
            state <= IDLE;
            done <= 0;
            accel_start <= 0;
            i <= 0; j <= 0;
            r <= 0; s <= 0;

            for (int i = 0; i < M; i++) begin
                for (int j = 0; j < N; j++) begin
                    C[i][j] <= 0;
                end
            end
        
            for (int r = 0; r < LANES; r++) begin
                for (int s = 0; s < N_MAX; s++) begin
                    a_lane[r][s] <= 0;
                    b_lane[r][s] <= 0;
                end
            end
        end
        
        else begin

        case(state)

        IDLE: begin
            done <= 0;
            accel_start <= 0;

            if(start) begin
                i <= 0;
                j <= 0;
                state <= LOAD;
            end
        end

        LOAD: begin

            for(lane=0; lane<LANES; lane=lane+1)
                for(k=0; k<K; k=k+1) begin

                    a_lane[lane][k] <= A[i][k];

                    if(j+lane < N)
                        b_lane[lane][k] <= B[k][j+lane];
                    else
                        b_lane[lane][k] <= 0;

                end

            state <= START;

        end

        START: begin
            accel_start <= 1;
            state <= RUN;
        end

        RUN: begin
            accel_start <= 0;

            if(accel_done)
                state <= STORE;
        end

        STORE: begin

            for(lane=0; lane<LANES; lane=lane+1)
                if(j+lane < N)
                    C[i][j+lane] <= res[lane];

            state <= NEXT;

        end

        NEXT: begin

            if(j + LANES < N) begin
                j <= j + LANES;
                state <= LOAD;
            end
            else if(i + 1 < M) begin
                i <= i + 1;
                j <= 0;
                state <= LOAD;
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
