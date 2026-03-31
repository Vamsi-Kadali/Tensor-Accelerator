`timescale 1ns / 1ps

module tb_uart_tensor_bridge;

    localparam CLKS_PER_BIT = 10;
    localparam WIDTH        = 16;
    localparam MAX_DIM      = 16;
    localparam ACC          = 2*WIDTH + $clog2(MAX_DIM);
    localparam DEPTH        = MAX_DIM * MAX_DIM;
    localparam ADDR_W       = $clog2(DEPTH);
    localparam DIM_W        = $clog2(MAX_DIM + 1);
    localparam TX_BYTES     = (ACC + 7) / 8;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst;

    reg  uart_rxd = 1'b1;
    wire uart_txd;

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

    reg signed [WIDTH-1:0] A_ref [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B_ref [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [ACC-1:0]   GOLD  [0:MAX_DIM-1][0:MAX_DIM-1];

    integer hadamard_mode;
    reg signed [WIDTH-1:0] scalar;
    reg signed [WIDTH-1:0] row_vec [0:MAX_DIM-1];
    reg signed [WIDTH-1:0] col_vec [0:MAX_DIM-1];

    integer errors;
    integer test;
    integer i, j, k;

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

    task automatic recv_byte (output [7:0] data);
        integer b;
        begin
            @(negedge uart_txd);

            repeat (CLKS_PER_BIT / 2 + CLKS_PER_BIT) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                data[b] = uart_txd;
                if (b < 7) repeat (CLKS_PER_BIT) @(posedge clk);
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

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

    task automatic randomize_matrices (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N
        );
        begin

            for (i = 0; i < MAX_DIM; i = i + 1)
            for (j = 0; j < MAX_DIM; j = j + 1) begin
                A_ref[i][j] = '0;
                B_ref[i][j] = '0;
            end

            if (op == 3'b000 || op == 3'b100) begin

                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < K; j = j + 1)
                A_ref[i][j] = signed'(8'($urandom()));

                for (i = 0; i < K; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                B_ref[i][j] = signed'(8'($urandom()));
            end
            else if (op == 3'b101) begin

                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                A_ref[i][j] = signed'(8'($urandom()));
            end
            else if (op == 3'b011) begin

                hadamard_mode = $urandom_range(0, 3);

                for (i = 0; i < M; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                A_ref[i][j] = signed'(8'($urandom()));

                case (hadamard_mode)
                0: begin
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                    B_ref[i][j] = signed'(8'($urandom()));
                end
                1: begin
                    scalar = signed'(8'($urandom()));
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                    B_ref[i][j] = scalar;
                end
                2: begin
                    for (j = 0; j < N; j = j + 1)
                    row_vec[j] = signed'(8'($urandom()));
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                    B_ref[i][j] = row_vec[j];
                end
                3: begin
                    for (i = 0; i < M; i = i + 1)
                    col_vec[i] = signed'(8'($urandom()));
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                    B_ref[i][j] = col_vec[i];
                end
            endcase
        end
        else begin

            for (i = 0; i < M; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                A_ref[i][j] = signed'(8'($urandom()));
                B_ref[i][j] = signed'(8'($urandom()));
            end
        end
    end
endtask

task automatic load_to_bram (
    input [2:0]       op,
    input [DIM_W-1:0] M, K, N
    );
    begin
        if (op == 3'b000 || op == 3'b100) begin

            for (i = 0; i < M; i = i + 1)
            for (j = 0; j < K; j = j + 1)
            uart_write_a(i * MAX_DIM + j, A_ref[i][j]);

            if (op == 3'b000) begin
                for (i = 0; i < K; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                uart_write_b(i * MAX_DIM + j, B_ref[i][j]);
            end
        end
        else if (op == 3'b101) begin

            for (i = 0; i < M; i = i + 1)
            for (j = 0; j < N; j = j + 1)
            uart_write_a(i * MAX_DIM + j, A_ref[i][j]);
        end
        else begin

            for (i = 0; i < M; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                uart_write_a(i * MAX_DIM + j, A_ref[i][j]);
                uart_write_b(i * MAX_DIM + j, B_ref[i][j]);
            end
        end
    end
endtask

task automatic compute_golden (
    input [2:0]       op,
    input [DIM_W-1:0] M, K, N
    );
    begin
        for (i = 0; i < M; i = i + 1)
        for (j = 0; j < N; j = j + 1) begin
            GOLD[i][j] = '0;
            case (op)
            3'b000: for (k = 0; k < K; k = k + 1)
            GOLD[i][j] = GOLD[i][j]
            + ACC'(signed'(A_ref[i][k]))
            * ACC'(signed'(B_ref[k][j]));
            3'b001: GOLD[i][j] = ACC'(signed'(A_ref[i][j]))
            + ACC'(signed'(B_ref[i][j]));
            3'b010: GOLD[i][j] = ACC'(signed'(A_ref[i][j]))
            - ACC'(signed'(B_ref[i][j]));
            3'b011: GOLD[i][j] = ACC'(signed'(A_ref[i][j]))
            * ACC'(signed'(B_ref[i][j]));
            3'b100: for (k = 0; k < K; k = k + 1)
            GOLD[i][j] = GOLD[i][j]
            + ACC'(signed'(A_ref[i][k]));
            3'b101: for (k = 0; k < M; k = k + 1)
            GOLD[i][j] = GOLD[i][j]
            + ACC'(signed'(A_ref[k][j]));
            default: GOLD[i][j] = '0;
        endcase
    end
end
endtask

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

reg [2:0]       op;
reg [DIM_W-1:0] M, K, N;

initial begin

    rst      = 1;
    errors   = 0;
    uart_rxd = 1'b1;
    repeat (20) @(posedge clk);
    rst = 0;
    repeat (5)  @(posedge clk);

    test = 0;
    A_ref[0][0]=1;  A_ref[0][1]=2;
    A_ref[1][0]=3;  A_ref[1][1]=4;
    B_ref[0][0]=5;  B_ref[0][1]=6;
    B_ref[1][0]=7;  B_ref[1][1]=8;
    run_test(3'b000, 2, 2, 2);

    test = 1;
    A_ref[0][0] = 16'sh0064;
    B_ref[0][0] = 16'shFF9C;
    run_test(3'b001, 1, 1, 1);

    test = 2;
    A_ref[0][0]=10; A_ref[0][1]=20;
    A_ref[1][0]=30; A_ref[1][1]=40;
    B_ref[0][0]=1;  B_ref[0][1]=2;
    B_ref[1][0]=3;  B_ref[1][1]=4;
    run_test(3'b010, 2, 2, 2);

    test = 3;
    A_ref[0][0]=3; A_ref[0][1]=4;
    A_ref[1][0]=5; A_ref[1][1]=6;
    B_ref[0][0]=2; B_ref[0][1]=3;
    B_ref[1][0]=4; B_ref[1][1]=5;
    run_test(3'b011, 2, 2, 2);

    test = 4;
    A_ref[0][0]=1; A_ref[0][1]=2; A_ref[0][2]=3;
    A_ref[1][0]=4; A_ref[1][1]=5; A_ref[1][2]=6;
    run_test(3'b100, 2, 3, 3);

    test = 5;
    A_ref[0][0]=1; A_ref[0][1]=2;
    A_ref[1][0]=3; A_ref[1][1]=4;
    run_test(3'b101, 2, 2, 2);

    test = 6;
    A_ref[0][0]=-3; A_ref[0][1]= 2;
    A_ref[1][0]= 1; A_ref[1][1]=-4;
    B_ref[0][0]= 5; B_ref[0][1]=-1;
    B_ref[1][0]=-2; B_ref[1][1]= 3;
    run_test(3'b000, 2, 2, 2);

    for (test = 7; test < 507; test = test + 1) begin

        M = DIM_W'($urandom_range(1, 4));
        K = DIM_W'($urandom_range(1, 4));
        N = DIM_W'($urandom_range(1, 4));

        case ($urandom_range(0, 5))
        0: op = 3'b000;
        1: op = 3'b001;
        2: op = 3'b010;
        3: op = 3'b011;
        4: op = 3'b100;
        5: op = 3'b101;
    endcase

    randomize_matrices(op, M, K, N);

    run_test(op, M, K, N);
end

if (errors == 0)
$display("\n*** ALL %0d TESTS PASSED ***\n", test);
else
$display("\n*** FAIL: %0d error(s) ***\n", errors);

$finish;
end

initial begin
    #100_000_000;
    $display("WATCHDOG: simulation timeout");
    $finish;
end

endmodule
