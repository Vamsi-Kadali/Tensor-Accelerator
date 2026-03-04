`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.03.2026 12:53:33
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

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam WIDTH = 16;
    localparam ACC   = 32;
    localparam N_MAX = 4;
    localparam LANES = 2;

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------
    reg rst;
    reg load;
    reg en;

    reg [2:0] op;
    reg scalar_en;
    reg [$clog2(N_MAX+1)-1:0] vec_len;

    reg signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1];

    wire signed [ACC-1:0] res [0:LANES-1];
    wire done;

    integer i, j;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    simd_array #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .load(load),
        .en(en),
        .op(op),
        .scalar_en(scalar_en),
        .vec_len(vec_len),
        .a(a),
        .b(b),
        .res(res),
        .done(done)
    );

    // ------------------------------------------------------------
    // Task: start operation
    // ------------------------------------------------------------
    task start_op;
        begin
            load = 1;
            en   = 0;
            #10;
            load = 0;
            en   = 1;
            wait(done);
            en = 0;
            #10;
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        // Init
        rst = 1;
        load = 0;
        en = 0;
        scalar_en = 0;
        vec_len = N_MAX;

        #20 rst = 0;

        // ========================================================
        // TEST 1: DOT PRODUCT
        // ========================================================
        op = 3'b000; // OP_MAC

        a[0] = '{1,2,3,4};
        b[0] = '{5,6,7,8};   // 70

        a[1] = '{2,2,2,2};
        b[1] = '{1,1,1,1};   // 8

        start_op();

        $display("DOT Lane0 = %0d (Expected 70)", res[0]);
        $display("DOT Lane1 = %0d (Expected 8)",  res[1]);

        // ========================================================
        // TEST 2: VECTOR ADD (element-wise, last element)
        // ========================================================
        op = 3'b001; // OP_ADD

        start_op();

        $display("ADD Lane0 = %0d (Expected 4+8=12)", res[0]);
        $display("ADD Lane1 = %0d (Expected 2+1=3)",  res[1]);

        // ========================================================
        // TEST 3: VECTOR SUM (reduction)
        // ========================================================
        op = 3'b100; // OP_SUM

        start_op();

        $display("SUM Lane0 = %0d (Expected 10)", res[0]);
        $display("SUM Lane1 = %0d (Expected 8)",  res[1]);

        // ========================================================
        // TEST 4: SCALAR MULTIPLY
        // ========================================================
        scalar_en = 1;
        op = 3'b011; // OP_MUL

        b[0][0] = 3; // scalar for lane 0
        b[1][0] = 4; // scalar for lane 1

        start_op();

        $display("SCALAR MUL Lane0 = %0d (Expected 4*3=12)", res[0]);
        $display("SCALAR MUL Lane1 = %0d (Expected 2*4=8)",  res[1]);

        #50 $finish;
    end

endmodule