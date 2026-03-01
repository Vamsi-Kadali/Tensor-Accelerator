`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.02.2026 20:24:58
// Design Name: 
// Module Name: tb
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


module tb;

    localparam WIDTH = 16;
    localparam ACC   = 32;
    localparam N_MAX = 4;
    localparam LANES = 2;
    localparam RUNS  = 10;

    reg clk;
    reg rst;
    reg start;

    reg [1:0] op;
    reg [$clog2(N_MAX+1)-1:0] vec_len;

    reg signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1];

    wire signed [ACC-1:0] res [0:LANES-1];
    wire done;

    integer i, j;
    integer run_count;

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    simd_unit #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .vec_len(vec_len),
        .a(a),
        .b(b),
        .res(res),
        .done(done)
    );

    initial begin
        rst = 1;
        start = 0;
        op = 2'b10;
        vec_len = N_MAX;
        run_count = 0;

        // Initial inputs
        for (i = 0; i < LANES; i = i + 1)
            for (j = 0; j < N_MAX; j = j + 1) begin
                a[i][j] = j + 1;
                b[i][j] = 1;
            end

        // Reset
        #20 rst = 0;

        // Hold start high (stress FSM)
        start = 1;

        repeat (RUNS) begin
            // Wait for completion
            @(posedge done);

            // Update inputs immediately AFTER job finishes
            // (safe because next load happens in FSM INIT)
            @(posedge clk);
            for (i = 0; i < LANES; i = i + 1)
                for (j = 0; j < N_MAX; j = j + 1) begin
                    a[i][j] = a[i][j] + 1;
                    b[i][j] = b[i][j] + 2;
                end

            run_count = run_count + 1;
        end

        start = 0;
        #100;
        $finish;
    end

endmodule