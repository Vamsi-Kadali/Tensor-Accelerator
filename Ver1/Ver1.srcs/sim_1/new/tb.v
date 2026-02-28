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

    // Parameters
    localparam WIDTH = 16;
    localparam ACC   = 32;
    localparam N_MAX = 4;     // max vector length for baseline_mac
    localparam LANES = 2;

    // Clock & reset
    reg clk;
    reg rst;
    reg start;

    // FSM signals
    wire en;
    wire clear;
    wire done;

    // SIMD signals
    wire simd_done;

    // Dummy opcode / N
    reg [1:0] op;
    reg [$clog2(N_MAX+1)-1:0] vec_len;

    // Input data
    reg signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1];

    wire signed [ACC-1:0] res [0:LANES-1];

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // FSM instance
    accel_fsm #(
        .N_W($clog2(N_MAX+1))
    ) fsm (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .N(vec_len),
        .datapath_done(simd_done),
        .en(en),
        .clear(clear),
        .done(done)
    );

    // SIMD array instance
    simd_array #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) simd (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .en(en),
        .vec_len(vec_len),
        .a(a),
        .b(b),
        .res(res),
        .done(simd_done)
    );

    integer i, j;
    integer run_count;

    initial begin
        // Initialize
        rst = 1;
        start = 0;
        op = 2'b10;       // placeholder opcode
        vec_len = N_MAX;

        // Fill initial input vectors
        for (i = 0; i < LANES; i = i + 1)
            for (j = 0; j < N_MAX; j = j + 1) begin
                a[i][j] = j + 1;
                b[i][j] = 1;
            end

        // Apply reset
        #20;
        rst = 0;

        // Start accelerator and hold start high
        start = 1;
        run_count = 0;

        // Wait for done, then update inputs automatically
        forever begin
            @(posedge done);  // wait for 1-cycle done pulse
            run_count = run_count + 1;

            // Update input vectors for next run
            for (i = 0; i < LANES; i = i + 1)
                for (j = 0; j < N_MAX; j = j + 1) begin
                    a[i][j] = a[i][j] + 1; // increment each element
                    b[i][j] = b[i][j] + 2; // increment differently
                end

            // Stop after 3 runs for simulation
            if (run_count == 3) begin
                start = 0;
                #200;
                $finish;
            end
        end
    end

endmodule