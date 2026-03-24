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



module tb_fpga_top_uart_random;

    // ================================================================
    // PARAMETERS
    // ================================================================
    localparam int WIDTH       = 16;
    localparam int MAX_DIM     = 16;
    localparam int N_MAX       = 16;
    localparam int LANES       = 8;
    localparam int TILE_R      = 2;
    localparam int TILE_C      = 4;

    localparam int ACC         = 2*WIDTH + $clog2(MAX_DIM); // 36
    localparam int DEPTH       = MAX_DIM * MAX_DIM;
    localparam int ADDR_W      = $clog2(DEPTH);
    localparam int ACC_BYTES   = (ACC + 7) / 8;             // 5 bytes

    localparam int CLK_PERIOD_NS = 10;
    localparam int BIT_TIME_NS   = 8680;                    // 100MHz / 115200 baud
    localparam int NUM_TESTS     = 50;

    // ================================================================
    // DUT SIGNALS
    // ================================================================
    logic clk_in   = 1'b0;
    logic rst      = 1'b1;
    logic uart_rxd = 1'b1;
    wire  uart_txd;

    // ================================================================
    // DUT
    // ================================================================
    fpga_top dut (
        .clk_in  (clk_in),
        .rst     (rst),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd)
    );

    always #(CLK_PERIOD_NS/2) clk_in = ~clk_in;

    // ================================================================
    // SCOREBOARD STORAGE
    // ================================================================
    logic signed [WIDTH-1:0] A    [0:MAX_DIM-1][0:MAX_DIM-1];
    logic signed [WIDTH-1:0] B    [0:MAX_DIM-1][0:MAX_DIM-1];
    logic signed [ACC-1:0]   GOLD [0:MAX_DIM-1][0:MAX_DIM-1];

    logic signed [ACC-1:0]   val;

    int i, j, k, test;
    int errors = 0;
    int hadamard_mode;
    logic signed [WIDTH-1:0] scalar;
    logic signed [WIDTH-1:0] row_vec [0:MAX_DIM-1];
    logic signed [WIDTH-1:0] col_vec [0:MAX_DIM-1];

    int M_len;
    int K_len;
    int N_len;
    logic [2:0] op;

    // ================================================================
    // TIMEOUT WATCHDOG
    // ================================================================
    initial begin
        #1_000_000_000;
        $display("TIMEOUT: simulation did not complete.");
        $finish;
    end

    // ================================================================
    // UART TX: HOST -> DUT
    // 8N1, LSB first
    // ================================================================
    task automatic uart_send_byte(input logic [7:0] data);
        int b;
        begin
            uart_rxd = 1'b0;              // start bit
            #(BIT_TIME_NS);

            for (b = 0; b < 8; b = b + 1) begin
                uart_rxd = data[b];
                #(BIT_TIME_NS);
            end

            uart_rxd = 1'b1;              // stop bit
            #(BIT_TIME_NS);
        end
    endtask

    // ================================================================
    // UART RX: DUT -> HOST
    // Proven-good bit-centre sampling method
    // ================================================================
    task automatic uart_recv_byte(output logic [7:0] data);
        int b;
        begin
            data = 8'h00;

            // Wait for the start bit
            @(negedge uart_txd);

            // Sample in the middle of the first data bit
            #(BIT_TIME_NS/2);

            for (b = 0; b < 8; b = b + 1) begin
                #(BIT_TIME_NS);
                data[b] = uart_txd;
            end

            // Stop bit time
            #(BIT_TIME_NS);
        end
    endtask

    // ================================================================
    // PROTOCOL HELPERS
    // ================================================================
    task automatic uart_set_dims(
        input int m,
        input int kdim,
        input int ndim,
        input logic [2:0] opv
    );
        begin
            uart_send_byte(8'h03);
            uart_send_byte(m[7:0]);
            uart_send_byte(kdim[7:0]);
            uart_send_byte(ndim[7:0]);
            uart_send_byte({5'b0, opv});
        end
    endtask

    task automatic uart_write_A(input int addr, input logic signed [WIDTH-1:0] data);
        begin
            uart_send_byte(8'h01);
            uart_send_byte(addr[15:8]);
            uart_send_byte(addr[7:0]);
            uart_send_byte(data[15:8]);
            uart_send_byte(data[7:0]);
        end
    endtask

    task automatic uart_write_B(input int addr, input logic signed [WIDTH-1:0] data);
        begin
            uart_send_byte(8'h02);
            uart_send_byte(addr[15:8]);
            uart_send_byte(addr[7:0]);
            uart_send_byte(data[15:8]);
            uart_send_byte(data[7:0]);
        end
    endtask

    task automatic uart_start_and_wait_ack;
        logic [7:0] ack;
        begin
            uart_send_byte(8'h04);
            uart_recv_byte(ack);

            if (ack !== 8'hAA) begin
                $display("ERROR: expected ACK 0xAA, got 0x%02h", ack);
                errors++;
            end
        end
    endtask

    task automatic uart_read_C(input int addr, output logic signed [ACC-1:0] data);
        logic [7:0] rx_byte;
        logic [8*ACC_BYTES-1:0] raw;
        int b;
        begin
            uart_send_byte(8'h05);
            uart_send_byte(addr[15:8]);
            uart_send_byte(addr[7:0]);

            raw = '0;
            for (b = 0; b < ACC_BYTES; b = b + 1) begin
                uart_recv_byte(rx_byte);
                raw = (raw << 8) | rx_byte;
            end

            data = raw[ACC-1:0];
        end
    endtask

    // ================================================================
    // RANDOM MATRIX GENERATION
    // ================================================================
    task automatic randomize_matrices;
        begin
            for (i = 0; i < MAX_DIM; i = i + 1)
            for (j = 0; j < MAX_DIM; j = j + 1) begin
                A[i][j] = '0;
                B[i][j] = '0;
                GOLD[i][j] = '0;
            end

            if (op == 3'b000 || op == 3'b100) begin
                for (i = 0; i < M_len; i = i + 1)
                for (j = 0; j < K_len; j = j + 1)
                    A[i][j] = $signed($urandom());

                if (op == 3'b000) begin
                    for (i = 0; i < K_len; i = i + 1)
                    for (j = 0; j < N_len; j = j + 1)
                        B[i][j] = $signed($urandom());
                end
            end
            else if (op == 3'b101) begin
                for (i = 0; i < M_len; i = i + 1)
                for (j = 0; j < N_len; j = j + 1)
                    A[i][j] = $signed($urandom());
            end
            else if (op == 3'b011) begin
                hadamard_mode = $urandom_range(0, 3);

                for (i = 0; i < M_len; i = i + 1)
                for (j = 0; j < N_len; j = j + 1)
                    A[i][j] = $signed($urandom());

                case (hadamard_mode)
                    0: begin
                        for (i = 0; i < M_len; i = i + 1)
                        for (j = 0; j < N_len; j = j + 1)
                            B[i][j] = $signed($urandom());
                    end
                    1: begin
                        scalar = $signed($urandom());
                        for (i = 0; i < M_len; i = i + 1)
                        for (j = 0; j < N_len; j = j + 1)
                            B[i][j] = scalar;
                    end
                    2: begin
                        for (j = 0; j < N_len; j = j + 1)
                            row_vec[j] = $signed($urandom());
                        for (i = 0; i < M_len; i = i + 1)
                        for (j = 0; j < N_len; j = j + 1)
                            B[i][j] = row_vec[j];
                    end
                    3: begin
                        for (i = 0; i < M_len; i = i + 1)
                            col_vec[i] = $signed($urandom());
                        for (i = 0; i < M_len; i = i + 1)
                        for (j = 0; j < N_len; j = j + 1)
                            B[i][j] = col_vec[i];
                    end
                endcase
            end
            else begin
                for (i = 0; i < M_len; i = i + 1)
                for (j = 0; j < N_len; j = j + 1) begin
                    A[i][j] = $signed($urandom());
                    B[i][j] = $signed($urandom());
                end
            end
        end
    endtask

    // ================================================================
    // GOLDEN MODEL
    // ================================================================
    task automatic compute_golden;
        begin
            for (i = 0; i < M_len; i = i + 1)
            for (j = 0; j < N_len; j = j + 1) begin
                GOLD[i][j] = '0;

                if (op == 3'b000) begin
                    for (k = 0; k < K_len; k = k + 1)
                        GOLD[i][j] += A[i][k] * B[k][j];
                end
                else if (op == 3'b001) begin
                    GOLD[i][j] = A[i][j] + B[i][j];
                end
                else if (op == 3'b010) begin
                    GOLD[i][j] = A[i][j] - B[i][j];
                end
                else if (op == 3'b011) begin
                    GOLD[i][j] = A[i][j] * B[i][j];
                end
                else if (op == 3'b100) begin
                    for (k = 0; k < K_len; k = k + 1)
                        GOLD[i][j] += A[i][k];
                end
                else if (op == 3'b101) begin
                    for (k = 0; k < M_len; k = k + 1)
                        GOLD[i][j] += A[k][j];
                end
            end
        end
    endtask

    // ================================================================
    // LOAD MATRICES VIA UART
    // ================================================================
    task automatic load_via_uart;
        begin
            if (op == 3'b000 || op == 3'b100) begin
                // Load A
                for (i = 0; i < M_len; i = i + 1)
                for (j = 0; j < K_len; j = j + 1)
                    uart_write_A(i * MAX_DIM + j, A[i][j]);

                // Load B only for matmul
                if (op == 3'b000) begin
                    for (i = 0; i < K_len; i = i + 1)
                    for (j = 0; j < N_len; j = j + 1)
                        uart_write_B(i * MAX_DIM + j, B[i][j]);
                end
            end
            else if (op == 3'b101) begin
                for (i = 0; i < M_len; i = i + 1)
                for (j = 0; j < N_len; j = j + 1)
                    uart_write_A(i * MAX_DIM + j, A[i][j]);
            end
            else begin
                for (i = 0; i < M_len; i = i + 1)
                for (j = 0; j < N_len; j = j + 1) begin
                    uart_write_A(i * MAX_DIM + j, A[i][j]);
                    uart_write_B(i * MAX_DIM + j, B[i][j]);
                end
            end
        end
    endtask

    // ================================================================
    // READ BACK AND CHECK
    // ================================================================
    task automatic compare_result_via_uart;
        begin
            for (i = 0; i < M_len; i = i + 1)
            for (j = 0; j < N_len; j = j + 1) begin
                uart_read_C(i * MAX_DIM + j, val);

                if (val !== GOLD[i][j]) begin
                    $display("ERROR TEST=%0d op=%b (%0d,%0d) DUT=%0d GOLD=%0d",
                             test, op, i, j, val, GOLD[i][j]);
                    errors++;
                end
            end
        end
    endtask

    // ================================================================
    // SINGLE RANDOM TEST
    // ================================================================
    task automatic run_one_test(input int tid);
        begin
            M_len = $urandom_range(1, 4);
            K_len = $urandom_range(1, 4);
            N_len = $urandom_range(1, 4);

            case ($urandom_range(0, 5))
                0: op = 3'b000;
                1: op = 3'b001;
                2: op = 3'b010;
                3: op = 3'b011;
                4: op = 3'b100;
                5: op = 3'b101;
            endcase

            $display("\n===== TEST %0d START  op=%b  M=%0d K=%0d N=%0d =====",
                     tid, op, M_len, K_len, N_len);

            randomize_matrices();
            compute_golden();

            uart_set_dims(M_len, K_len, N_len, op);
            load_via_uart();
            uart_start_and_wait_ack();
            compare_result_via_uart();

            if (errors == 0)
                $display("TEST %0d PASS", tid);
            else
                $display("TEST %0d FAIL", tid);
        end
    endtask

    // ================================================================
    // MAIN
    // ================================================================
    initial begin
        rst = 1'b1;
        uart_rxd = 1'b1;
        errors = 0;

        repeat (20) @(posedge clk_in);
        rst = 1'b0;
        repeat (20) @(posedge clk_in);

        for (test = 0; test < NUM_TESTS; test = test + 1) begin
            run_one_test(test);
        end

        if (errors == 0)
            $display("\nALL TESTS PASSED\n");
        else
            $display("\nFAIL: %0d errors\n", errors);

        $finish;
    end

endmodule