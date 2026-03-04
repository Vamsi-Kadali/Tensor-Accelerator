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

    // -------------------------
    // Parameters
    // -------------------------
    localparam WIDTH = 16;
    localparam ACC   = 32;
    localparam N_MAX = 8;
    localparam LANES = 8;

    // -------------------------
    // Signals
    // -------------------------
    logic clk;
    logic rst;
    logic start;

    logic [2:0] op;
    logic scalar_en;
    logic [$clog2(N_MAX+1)-1:0] vec_len;

    logic signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1];
    logic signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1];

    logic signed [ACC-1:0] res [0:LANES-1];
    logic busy;
    logic done;

    integer i, j;

    // -------------------------
    // DUT
    // -------------------------
    accel_top #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .scalar_en(scalar_en),
        .vec_len(vec_len),
        .a(a),
        .b(b),
        .res(res),
        .busy(busy),
        .done(done)
    );

    // -------------------------
    // Clock
    // -------------------------
    always #5 clk = ~clk;

    // -------------------------
    // Test
    // -------------------------
    initial begin
        clk = 0;
        rst = 1;
        start = 0;

        // Reset
        #20;
        rst = 0;

        // -------------------------
        // Load data
        // -------------------------
        for (i = 0; i < LANES; i++) begin
            for (j = 0; j < N_MAX; j++) begin
                a[i][j] = j + 1;     // 1..8
                b[i][j] = i + 1;     // constant per lane
            end
        end

        vec_len   = 8;
        scalar_en = 0;
        op        = 3'b000; // OP_MAC

        // Start
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for completion
        wait(done);
        @(posedge clk);

        // -------------------------
        // Check results
        // -------------------------
        $display("=== SIMD RESULTS ===");
        for (i = 0; i < LANES; i++) begin
            $display("Lane %0d result = %0d", i, res[i]);

            if (res[i] !== 36 * (i + 1)) begin
                $display("❌ ERROR lane %0d: expected %0d", i, 36*(i+1));
                $fatal;
            end
        end

        $display("✅ ALL LANES PASSED");
        #20;
        $finish;
    end

endmodule