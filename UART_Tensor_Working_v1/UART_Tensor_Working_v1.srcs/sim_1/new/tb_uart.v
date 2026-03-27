`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.03.2026 22:24:22
// Design Name: 
// Module Name: tb_uart
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

`timescale 1ns / 1ps
// =============================================================================
//  tb_uart_tensor_bridge.sv
//
//  Tests uart_tensor_bridge, which internally instantiates tensor_top.
//  The testbench only touches four top-level signals:
//      clk, rst, uart_rxd (TB drives), uart_txd (TB monitors)
//
//  Structure mirrors tb_tensor_top_bram_random:
//    - Dedicated tasks for randomization, loading, golden model, comparison
//    - Fixed directed tests first, then a randomised stress loop
//    - All UART framing is hidden inside send_byte / recv_byte primitives
//
//  UART frame: start(0) + D[0..7] (LSB-first) + stop(1) = 10 bits
//  Each bit = CLKS_PER_BIT clock periods.
//
//  Protocol (host → DUT):
//    WRITE_A : [0x01][addr][data_hi][data_lo]  → ACK(0xAA)
//    WRITE_B : [0x02][addr][data_hi][data_lo]  → ACK(0xAA)
//    RUN     : [0x03][op][M][K][N]             → ACK(0xAA) after compute
//    READ_C  : [0x04][addr]                    → TX_BYTES bytes MSB-first
// =============================================================================

module tb_uart_tensor_bridge;

    // =========================================================================
    // Parameters  (must match the DUT)
    // =========================================================================
    localparam CLKS_PER_BIT = 10;
    localparam WIDTH        = 16;
    localparam MAX_DIM      = 16;
    localparam ACC          = 2*WIDTH + $clog2(MAX_DIM);   // 36
    localparam DEPTH        = MAX_DIM * MAX_DIM;           // 256
    localparam ADDR_W       = $clog2(DEPTH);               // 8
    localparam DIM_W        = $clog2(MAX_DIM + 1);         // 5
    localparam TX_BYTES     = (ACC + 7) / 8;               // 5

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    reg rst;

    // =========================================================================
    // Serial lines
    // =========================================================================
    reg  uart_rxd = 1'b1;   // TB → DUT  (idle HIGH)
    wire uart_txd;           // DUT → TB

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    uart_tensor_bridge #(
        .CLKS_PER_BIT (CLKS_PER_BIT),
        .WIDTH        (WIDTH),
        .MAX_DIM      (MAX_DIM),
        .ACC          (ACC),
        .DEPTH        (DEPTH)
    ) u_dut (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd)
    );

    // =========================================================================
    // Reference storage  (mirrors the local arrays in tb_tensor_top_bram_random)
    // =========================================================================
    reg signed [WIDTH-1:0] A_ref [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B_ref [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [ACC-1:0]   GOLD  [0:MAX_DIM-1][0:MAX_DIM-1];

    // Hadamard sub-mode tracking (matches tb_tensor_top_bram_random)
    integer hadamard_mode;
    reg signed [WIDTH-1:0] scalar;
    reg signed [WIDTH-1:0] row_vec [0:MAX_DIM-1];
    reg signed [WIDTH-1:0] col_vec [0:MAX_DIM-1];

    integer errors;
    integer test;
    integer i, j, k;

    // =========================================================================
    // ── UART PRIMITIVES ───────────────────────────────────────────────────────
    // =========================================================================

    // Send one byte: start bit → 8 data bits (LSB first) → stop bit
    task automatic send_byte (input [7:0] data);
        integer b;
        begin
            uart_rxd = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rxd = data[b];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            uart_rxd = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // Receive one byte: wait for start-bit falling edge, sample each data bit
    task automatic recv_byte (output [7:0] data);
        integer b;
        begin
            @(negedge uart_txd);
            // Align to centre of bit-0
            repeat (CLKS_PER_BIT / 2 + CLKS_PER_BIT) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                data[b] = uart_txd;
                if (b < 7) repeat (CLKS_PER_BIT) @(posedge clk);
            end
            repeat (CLKS_PER_BIT) @(posedge clk);   // consume stop bit
        end
    endtask

    // Receive one byte and verify it equals ACK (0xAA)
    task automatic recv_ack ();
        reg [7:0] ack;
        begin
            recv_byte(ack);
            if (ack !== 8'hAA) begin
                $display("ERROR test=%0d: expected ACK=0xAA, got 0x%02X", test, ack);
                errors = errors + 1;
            end
        end
    endtask

    // =========================================================================
    // ── PROTOCOL HELPERS ──────────────────────────────────────────────────────
    // =========================================================================

    // WRITE_A: [0x01][addr][data_hi][data_lo] → ACK
    task automatic uart_write_a (
        input [ADDR_W-1:0]       addr,
        input signed [WIDTH-1:0] data
    );
        begin
            send_byte(8'h01);
            send_byte(8'(addr));
            send_byte(data[15:8]);
            send_byte(data[7:0]);
            recv_ack();
        end
    endtask

    // WRITE_B: [0x02][addr][data_hi][data_lo] → ACK
    task automatic uart_write_b (
        input [ADDR_W-1:0]       addr,
        input signed [WIDTH-1:0] data
    );
        begin
            send_byte(8'h02);
            send_byte(8'(addr));
            send_byte(data[15:8]);
            send_byte(data[7:0]);
            recv_ack();
        end
    endtask

    // RUN: [0x03][op][M][K][N] → ACK (blocks until tensor_top asserts done)
    task automatic uart_run (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N
    );
        begin
            send_byte(8'h03);
            send_byte({5'b0, op});
            send_byte({3'b0, M});
            send_byte({3'b0, K});
            send_byte({3'b0, N});
            recv_ack();
        end
    endtask

    // READ_C: [0x04][addr] → TX_BYTES bytes MSB-first → reassembled ACC-bit value
    task automatic uart_read_c (
        input  [ADDR_W-1:0] addr,
        output [ACC-1:0]    c_val
    );
        reg [7:0] rx;
        integer   b;
        begin
            send_byte(8'h04);
            send_byte(8'(addr));
            c_val = '0;
            for (b = TX_BYTES - 1; b >= 0; b = b - 1) begin
                recv_byte(rx);
                c_val[b*8 +: 8] = rx;
            end
        end
    endtask

    // =========================================================================
    // ── RANDOMIZE  (mirrors randomize_matrices in tb_tensor_top_bram_random) ─
    // =========================================================================
    // Fills A_ref and B_ref according to the current op, M/K/N dimensions.
    // Clears unused entries to zero first.  Hadamard sub-modes are preserved.
    task automatic randomize_matrices (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N
    );
        begin
            // Clear all reference entries
            for (i = 0; i < MAX_DIM; i = i + 1)
            for (j = 0; j < MAX_DIM; j = j + 1) begin
                A_ref[i][j] = '0;
                B_ref[i][j] = '0;
            end

            if (op == 3'b000 || op == 3'b100) begin
                // MATMUL / ROW_ACCUM: A is M×K, B is K×N
                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < K; j = j + 1)
                    A_ref[i][j] = signed'(8'($urandom()));   // sign-extend 8→16

                for (i = 0; i < K; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    B_ref[i][j] = signed'(8'($urandom()));
            end
            else if (op == 3'b101) begin
                // COL_ACCUM: only A (M×N) is needed
                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    A_ref[i][j] = signed'(8'($urandom()));
            end
            else if (op == 3'b011) begin
                // HADAMARD: four sub-modes matching tb_tensor_top_bram_random
                hadamard_mode = $urandom_range(0, 3);

                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    A_ref[i][j] = signed'(8'($urandom()));

                case (hadamard_mode)
                    0: begin   // element-wise random B
                        for (i = 0; i < M; i = i + 1)
                        for (j = 0; j < N; j = j + 1)
                            B_ref[i][j] = signed'(8'($urandom()));
                    end
                    1: begin   // scalar B (same value in every cell)
                        scalar = signed'(8'($urandom()));
                        for (i = 0; i < M; i = i + 1)
                        for (j = 0; j < N; j = j + 1)
                            B_ref[i][j] = scalar;
                    end
                    2: begin   // row-vector B (same row repeated)
                        for (j = 0; j < N; j = j + 1)
                            row_vec[j] = signed'(8'($urandom()));
                        for (i = 0; i < M; i = i + 1)
                        for (j = 0; j < N; j = j + 1)
                            B_ref[i][j] = row_vec[j];
                    end
                    3: begin   // col-vector B (same column repeated)
                        for (i = 0; i < M; i = i + 1)
                            col_vec[i] = signed'(8'($urandom()));
                        for (i = 0; i < M; i = i + 1)
                        for (j = 0; j < N; j = j + 1)
                            B_ref[i][j] = col_vec[i];
                    end
                endcase
            end
            else begin
                // ADD / SUB: both A and B are M×N
                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    A_ref[i][j] = signed'(8'($urandom()));
                    B_ref[i][j] = signed'(8'($urandom()));
                end
            end
        end
    endtask

    // =========================================================================
    // ── LOAD BRAM  (mirrors load_to_bram in tb_tensor_top_bram_random) ───────
    // =========================================================================
    // Sends WRITE_A / WRITE_B packets over UART to populate the DUT's BRAMs.
    task automatic load_to_bram (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N
    );
        begin
            if (op == 3'b000 || op == 3'b100) begin
                // MATMUL / ROW_ACCUM: A is M×K
                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < K; j = j + 1)
                    uart_write_a(i * MAX_DIM + j, A_ref[i][j]);

                // MATMUL only: B is K×N
                if (op == 3'b000) begin
                    for (i = 0; i < K; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                        uart_write_b(i * MAX_DIM + j, B_ref[i][j]);
                end
            end
            else if (op == 3'b101) begin
                // COL_ACCUM: only A (M×N)
                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    uart_write_a(i * MAX_DIM + j, A_ref[i][j]);
            end
            else begin
                // ADD / SUB / HADAMARD: both A and B are M×N
                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    uart_write_a(i * MAX_DIM + j, A_ref[i][j]);
                    uart_write_b(i * MAX_DIM + j, B_ref[i][j]);
                end
            end
        end
    endtask

    // =========================================================================
    // ── GOLDEN MODEL  (mirrors compute_golden in tb_tensor_top_bram_random) ──
    // =========================================================================
    task automatic compute_golden (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N
    );
        begin
            for (i = 0; i < M; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                GOLD[i][j] = '0;
                case (op)
                    3'b000: for (k = 0; k < K; k = k + 1)   // MATMUL
                                GOLD[i][j] = GOLD[i][j]
                                           + ACC'(signed'(A_ref[i][k]))
                                           * ACC'(signed'(B_ref[k][j]));
                    3'b001: GOLD[i][j] = ACC'(signed'(A_ref[i][j]))   // ADD
                                       + ACC'(signed'(B_ref[i][j]));
                    3'b010: GOLD[i][j] = ACC'(signed'(A_ref[i][j]))   // SUB
                                       - ACC'(signed'(B_ref[i][j]));
                    3'b011: GOLD[i][j] = ACC'(signed'(A_ref[i][j]))   // HADAMARD
                                       * ACC'(signed'(B_ref[i][j]));
                    3'b100: for (k = 0; k < K; k = k + 1)   // ROW_ACCUM
                                GOLD[i][j] = GOLD[i][j]
                                           + ACC'(signed'(A_ref[i][k]));
                    3'b101: for (k = 0; k < M; k = k + 1)   // COL_ACCUM
                                GOLD[i][j] = GOLD[i][j]
                                           + ACC'(signed'(A_ref[k][j]));
                    default: GOLD[i][j] = '0;
                endcase
            end
        end
    endtask

    // =========================================================================
    // ── COMPARE  (mirrors compare_result in tb_tensor_top_bram_random) ───────
    // =========================================================================
    // Reads every C[i][j] back via UART READ_C and checks against GOLD.
    task automatic compare_result (
        input [2:0]       op,
        input [DIM_W-1:0] M, N
    );
        reg [ACC-1:0]        c_raw;
        reg signed [ACC-1:0] c_got;
        begin
            for (i = 0; i < M; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                uart_read_c(i * MAX_DIM + j, c_raw);
                c_got = $signed(c_raw);
                if (c_got !== GOLD[i][j]) begin
                    $display("ERROR TEST=%0d op=%b (%0d,%0d) DUT=%0d GOLD=%0d",
                             test, op, i, j, c_got, GOLD[i][j]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    // =========================================================================
    // ── RUN ONE COMPLETE TEST  (load → run → compare) ────────────────────────
    // =========================================================================
    task automatic run_test (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N
    );
        begin
            load_to_bram   (op, M, K, N);
            compute_golden (op, M, K, N);
            uart_run       (op, M, K, N);
            compare_result (op, M, N);
            $display("Test %0d complete (op=%b M=%0d K=%0d N=%0d)", test, op, M, K, N);
        end
    endtask

    // =========================================================================
    // ── MAIN TEST SEQUENCE ────────────────────────────────────────────────────
    // =========================================================================
    reg [2:0]       op;
    reg [DIM_W-1:0] M, K, N;

    initial begin
        // ------------------------------------------------------------------
        // Reset
        // ------------------------------------------------------------------
        rst      = 1;
        errors   = 0;
        uart_rxd = 1'b1;
        repeat (20) @(posedge clk);
        rst = 0;
        repeat (5)  @(posedge clk);

        // ==================================================================
        // DIRECTED (FIXED) TESTS
        // ==================================================================

        // ------------------------------------------------------------------
        // Test 0: 2×2 MATMUL with known values
        //   A = [[1,2],[3,4]]  B = [[5,6],[7,8]]
        //   Expected C = [[19,22],[43,50]]
        // ------------------------------------------------------------------
        test = 0;
        A_ref[0][0]=1;  A_ref[0][1]=2;
        A_ref[1][0]=3;  A_ref[1][1]=4;
        B_ref[0][0]=5;  B_ref[0][1]=6;
        B_ref[1][0]=7;  B_ref[1][1]=8;
        run_test(3'b000, 2, 2, 2);

        // ------------------------------------------------------------------
        // Test 1: 1×1 ADD with positive + negative (result = 0)
        //   A = 100, B = -100  →  C = 0
        // ------------------------------------------------------------------
        test = 1;
        A_ref[0][0] = 16'sh0064;   //  100
        B_ref[0][0] = 16'shFF9C;   // -100
        run_test(3'b001, 1, 1, 1);

        // ------------------------------------------------------------------
        // Test 2: 2×2 SUB with known values
        //   A = [[10,20],[30,40]]  B = [[1,2],[3,4]]
        //   Expected C = [[9,18],[27,36]]
        // ------------------------------------------------------------------
        test = 2;
        A_ref[0][0]=10; A_ref[0][1]=20;
        A_ref[1][0]=30; A_ref[1][1]=40;
        B_ref[0][0]=1;  B_ref[0][1]=2;
        B_ref[1][0]=3;  B_ref[1][1]=4;
        run_test(3'b010, 2, 2, 2);

        // ------------------------------------------------------------------
        // Test 3: 2×2 HADAMARD (element-wise multiply) with known values
        //   A = [[3,4],[5,6]]  B = [[2,3],[4,5]]
        //   Expected C = [[6,12],[20,30]]
        // ------------------------------------------------------------------
        test = 3;
        A_ref[0][0]=3; A_ref[0][1]=4;
        A_ref[1][0]=5; A_ref[1][1]=6;
        B_ref[0][0]=2; B_ref[0][1]=3;
        B_ref[1][0]=4; B_ref[1][1]=5;
        run_test(3'b011, 2, 2, 2);

        // ------------------------------------------------------------------
        // Test 4: 2×3 ROW_ACCUM - each C[i][j] = sum of row i of A
        //   A = [[1,2,3],[4,5,6]]
        //   Expected: C[0][*]=6, C[1][*]=15
        // ------------------------------------------------------------------
        test = 4;
        A_ref[0][0]=1; A_ref[0][1]=2; A_ref[0][2]=3;
        A_ref[1][0]=4; A_ref[1][1]=5; A_ref[1][2]=6;
        run_test(3'b100, 2, 3, 3);

        // ------------------------------------------------------------------
        // Test 5: 2×2 COL_ACCUM - each C[i][j] = sum of column j of A
        //   A = [[1,2],[3,4]]
        //   Expected: C[*][0]=4, C[*][1]=6
        // ------------------------------------------------------------------
        test = 5;
        A_ref[0][0]=1; A_ref[0][1]=2;
        A_ref[1][0]=3; A_ref[1][1]=4;
        run_test(3'b101, 2, 2, 2);

        // ------------------------------------------------------------------
        // Test 6: 2×2 MATMUL with signed (negative) values
        //   A = [[-3,2],[1,-4]]  B = [[5,-1],[-2,3]]
        //   Expected: C[0][0]=-19, C[0][1]=9, C[1][0]=13, C[1][1]=-13
        // ------------------------------------------------------------------
        test = 6;
        A_ref[0][0]=-3; A_ref[0][1]= 2;
        A_ref[1][0]= 1; A_ref[1][1]=-4;
        B_ref[0][0]= 5; B_ref[0][1]=-1;
        B_ref[1][0]=-2; B_ref[1][1]= 3;
        run_test(3'b000, 2, 2, 2);

        // ==================================================================
        // RANDOMISED STRESS TESTS  (500 iterations, matching tb_bram style)
        // ==================================================================
        for (test = 7; test < 507; test = test + 1) begin

            // Random dimensions (small to keep simulation time manageable)
            M = DIM_W'($urandom_range(1, 4));
            K = DIM_W'($urandom_range(1, 4));
            N = DIM_W'($urandom_range(1, 4));

            // Random operation
            case ($urandom_range(0, 5))
                0: op = 3'b000;   // MATMUL
                1: op = 3'b001;   // ADD
                2: op = 3'b010;   // SUB
                3: op = 3'b011;   // HADAMARD
                4: op = 3'b100;   // ROW_ACCUM
                5: op = 3'b101;   // COL_ACCUM
            endcase

            // Populate A_ref / B_ref with random signed 8-bit values
            randomize_matrices(op, M, K, N);

            // Full test: UART load → compute reference → trigger DUT → verify
            run_test(op, M, K, N);
        end

        // ==================================================================
        // Summary
        // ==================================================================
        if (errors == 0)
            $display("\n*** ALL %0d TESTS PASSED ***\n", test);
        else
            $display("\n*** FAIL: %0d error(s) ***\n", errors);

        $finish;
    end

    // =========================================================================
    // Watchdog - abort if simulation hangs
    // =========================================================================
    initial begin
        #100_000_000;
        $display("WATCHDOG: simulation timeout");
        $finish;
    end

endmodule