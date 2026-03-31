`timescale 1ns / 1ps

module tb_uart_tensor_bridge;

    localparam CLKS_PER_BIT = 10;
    localparam WIDTH        = 16;
    localparam MAX_DIM      = 64;
    localparam MAX_DEPTH    = 8;
    localparam ACC          = 2*WIDTH + $clog2(MAX_DIM);
    localparam DEPTH        = MAX_DEPTH * MAX_DIM * MAX_DIM;
    localparam ADDR_W       = $clog2(DEPTH);
    localparam DIM_W        = $clog2(MAX_DIM + 1);
    localparam DEP_W        = $clog2(MAX_DEPTH + 1);
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
        .MAX_DEPTH    (MAX_DEPTH),
        .ACC          (ACC),
        .DEPTH        (DEPTH)
    ) u_dut (
        .clk      (clk),
        .rst_l    (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd)
    );

    reg signed [WIDTH-1:0] A_ref [0:MAX_DEPTH-1][0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B_ref [0:MAX_DEPTH-1][0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [ACC-1:0]   GOLD  [0:MAX_DEPTH-1][0:MAX_DIM-1][0:MAX_DIM-1];

    integer hadamard_mode;
    reg signed [WIDTH-1:0] scalar;
    reg signed [WIDTH-1:0] row_vec [0:MAX_DIM-1];
    reg signed [WIDTH-1:0] col_vec [0:MAX_DIM-1];

    integer errors;
    integer test;
    integer i, j, k, dd;

    task automatic send_byte (input [7:0] data);
        integer b;
        begin
            @(negedge clk);
            uart_rxd = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rxd = data[b];
                repeat (CLKS_PER_BIT) @(negedge clk);
            end
            uart_rxd = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge clk);
        end
    endtask

    task automatic recv_byte (output [7:0] data);
        integer b;
        begin
            @(negedge uart_txd);
            repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                data[b] = uart_txd;
                if (b < 7)
                    repeat (CLKS_PER_BIT) @(posedge clk);
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
            send_byte(8'(addr[ADDR_W-1:8]));
            send_byte(8'(addr[7:0]));
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
            send_byte(8'(addr[ADDR_W-1:8]));
            send_byte(8'(addr[7:0]));
            send_byte(data[15:8]);
            send_byte(data[7:0]);
            recv_ack();
        end
    endtask

    task automatic uart_run (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N,
        input [DEP_W-1:0] D
    );
        begin
            send_byte(8'h03);
            send_byte(op);
            send_byte(M);
            send_byte(K);
            send_byte(N);
            send_byte(D);
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
            send_byte(8'(addr[ADDR_W-1:8]));
            send_byte(8'(addr[7:0]));
            c_val = '0;
            for (b = TX_BYTES - 1; b >= 0; b = b - 1) begin
                recv_byte(rx);
                c_val[b*8 +: 8] = rx;
            end
        end
    endtask

    function automatic [ADDR_W-1:0] flat_addr(
        input int d_idx, row, col
    );
        flat_addr = d_idx * MAX_DIM * MAX_DIM + row * MAX_DIM + col;
    endfunction

    task automatic randomize_matrices (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N,
        input [DEP_W-1:0] D
    );
        begin
            for (dd = 0; dd < MAX_DEPTH; dd = dd + 1)
            for (i  = 0; i  < MAX_DIM;   i  = i  + 1)
            for (j  = 0; j  < MAX_DIM;   j  = j  + 1) begin
                A_ref[dd][i][j] = '0;
                B_ref[dd][i][j] = '0;
            end

            for (dd = 0; dd < D; dd = dd + 1) begin
                if (op == 3'b000 || op == 3'b100) begin
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < K; j = j + 1)
                        A_ref[dd][i][j] = signed'(8'($urandom()));
                    for (i = 0; i < K; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                        B_ref[dd][i][j] = signed'(8'($urandom()));
                end
                else if (op == 3'b101) begin
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                        A_ref[dd][i][j] = signed'(8'($urandom()));
                end
                else if (op == 3'b011) begin
                    hadamard_mode = $urandom_range(0, 3);
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                        A_ref[dd][i][j] = signed'(8'($urandom()));
                    case (hadamard_mode)
                        0: for (i = 0; i < M; i = i + 1)
                           for (j = 0; j < N; j = j + 1)
                               B_ref[dd][i][j] = signed'(8'($urandom()));
                        1: begin
                               scalar = signed'(8'($urandom()));
                               for (i = 0; i < M; i = i + 1)
                               for (j = 0; j < N; j = j + 1)
                                   B_ref[dd][i][j] = scalar;
                           end
                        2: begin
                               for (j = 0; j < N; j = j + 1)
                                   row_vec[j] = signed'(8'($urandom()));
                               for (i = 0; i < M; i = i + 1)
                               for (j = 0; j < N; j = j + 1)
                                   B_ref[dd][i][j] = row_vec[j];
                           end
                        3: begin
                               for (i = 0; i < M; i = i + 1)
                                   col_vec[i] = signed'(8'($urandom()));
                               for (i = 0; i < M; i = i + 1)
                               for (j = 0; j < N; j = j + 1)
                                   B_ref[dd][i][j] = col_vec[i];
                           end
                    endcase
                end
                else begin
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1) begin
                        A_ref[dd][i][j] = signed'(8'($urandom()));
                        B_ref[dd][i][j] = signed'(8'($urandom()));
                    end
                end
            end
        end
    endtask

    task automatic load_to_bram (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N,
        input [DEP_W-1:0] D
    );
        begin
            for (dd = 0; dd < D; dd = dd + 1) begin
                if (op == 3'b000 || op == 3'b100) begin
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < K; j = j + 1)
                        uart_write_a(flat_addr(dd, i, j), A_ref[dd][i][j]);
                    if (op == 3'b000)
                        for (i = 0; i < K; i = i + 1)
                        for (j = 0; j < N; j = j + 1)
                            uart_write_b(flat_addr(dd, i, j), B_ref[dd][i][j]);
                end
                else if (op == 3'b101) begin
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                        uart_write_a(flat_addr(dd, i, j), A_ref[dd][i][j]);
                end
                else begin
                    for (i = 0; i < M; i = i + 1)
                    for (j = 0; j < N; j = j + 1) begin
                        uart_write_a(flat_addr(dd, i, j), A_ref[dd][i][j]);
                        uart_write_b(flat_addr(dd, i, j), B_ref[dd][i][j]);
                    end
                end
            end
        end
    endtask

    task automatic compute_golden (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N,
        input [DEP_W-1:0] D
    );
        begin
            for (dd = 0; dd < D; dd = dd + 1)
            for (i  = 0; i  < M; i  = i  + 1)
            for (j  = 0; j  < N; j  = j  + 1) begin
                GOLD[dd][i][j] = '0;
                case (op)
                    3'b000: for (k = 0; k < K; k = k + 1)
                                GOLD[dd][i][j] = GOLD[dd][i][j]
                                    + ACC'(signed'(A_ref[dd][i][k]))
                                    * ACC'(signed'(B_ref[dd][k][j]));
                    3'b001: GOLD[dd][i][j] = ACC'(signed'(A_ref[dd][i][j]))
                                           + ACC'(signed'(B_ref[dd][i][j]));
                    3'b010: GOLD[dd][i][j] = ACC'(signed'(A_ref[dd][i][j]))
                                           - ACC'(signed'(B_ref[dd][i][j]));
                    3'b011: GOLD[dd][i][j] = ACC'(signed'(A_ref[dd][i][j]))
                                           * ACC'(signed'(B_ref[dd][i][j]));
                    3'b100: for (k = 0; k < K; k = k + 1)
                                GOLD[dd][i][j] = GOLD[dd][i][j]
                                    + ACC'(signed'(A_ref[dd][i][k]));
                    3'b101: for (k = 0; k < M; k = k + 1)
                                GOLD[dd][i][j] = GOLD[dd][i][j]
                                    + ACC'(signed'(A_ref[dd][k][j]));
                    default: GOLD[dd][i][j] = '0;
                endcase
            end
        end
    endtask

    task automatic compare_result (
        input [2:0]       op,
        input [DIM_W-1:0] M, N,
        input [DEP_W-1:0] D
    );
        reg [ACC-1:0]        c_raw;
        reg signed [ACC-1:0] c_got;
        begin
            for (dd = 0; dd < D; dd = dd + 1)
            for (i  = 0; i  < M; i  = i  + 1)
            for (j  = 0; j  < N; j  = j  + 1) begin
                uart_read_c(flat_addr(dd, i, j), c_raw);
                c_got = $signed(c_raw);
                if (c_got !== GOLD[dd][i][j]) begin
                    $display("ERROR TEST=%0d op=%b d=%0d (%0d,%0d) DUT=%0d GOLD=%0d",
                             test, op, dd, i, j, c_got, GOLD[dd][i][j]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task automatic run_test (
        input [2:0]       op,
        input [DIM_W-1:0] M, K, N,
        input [DEP_W-1:0] D
    );
        begin
            load_to_bram   (op, M, K, N, D);
            compute_golden (op, M, K, N, D);
            uart_run       (op, M, K, N, D);
            compare_result (op, M, N, D);
            $display("Test %0d ok  op=%b M=%0d K=%0d N=%0d D=%0d", test, op, M, K, N, D);
        end
    endtask

    reg [2:0]       op;
    reg [DIM_W-1:0] M, K, N;
    reg [DEP_W-1:0] D;

    initial begin
        rst      = 0;
        errors   = 0;
        uart_rxd = 1'b1;
        repeat (20) @(posedge clk);
        rst = 1;
        repeat (5)  @(posedge clk);

        test = 0;
        A_ref[0][0][0]=1;  A_ref[0][0][1]=2;
        A_ref[0][1][0]=3;  A_ref[0][1][1]=4;
        B_ref[0][0][0]=5;  B_ref[0][0][1]=6;
        B_ref[0][1][0]=7;  B_ref[0][1][1]=8;
        run_test(3'b000, 2, 2, 2, 1);

        test = 1;
        A_ref[0][0][0] = 16'sh0064;
        B_ref[0][0][0] = 16'shFF9C;
        run_test(3'b001, 1, 1, 1, 1);

        test = 2;
        A_ref[0][0][0]=10; A_ref[0][0][1]=20;
        A_ref[0][1][0]=30; A_ref[0][1][1]=40;
        B_ref[0][0][0]=1;  B_ref[0][0][1]=2;
        B_ref[0][1][0]=3;  B_ref[0][1][1]=4;
        run_test(3'b010, 2, 2, 2, 1);

        test = 3;
        A_ref[0][0][0]=3; A_ref[0][0][1]=4;
        A_ref[0][1][0]=5; A_ref[0][1][1]=6;
        B_ref[0][0][0]=2; B_ref[0][0][1]=3;
        B_ref[0][1][0]=4; B_ref[0][1][1]=5;
        run_test(3'b011, 2, 2, 2, 1);

        test = 4;
        A_ref[0][0][0]=1; A_ref[0][0][1]=2; A_ref[0][0][2]=3;
        A_ref[0][1][0]=4; A_ref[0][1][1]=5; A_ref[0][1][2]=6;
        run_test(3'b100, 2, 3, 3, 1);

        test = 5;
        A_ref[0][0][0]=1; A_ref[0][0][1]=2;
        A_ref[0][1][0]=3; A_ref[0][1][1]=4;
        run_test(3'b101, 2, 2, 2, 1);

        test = 6;
        A_ref[0][0][0]=-3; A_ref[0][0][1]= 2;
        A_ref[0][1][0]= 1; A_ref[0][1][1]=-4;
        B_ref[0][0][0]= 5; B_ref[0][0][1]=-1;
        B_ref[0][1][0]=-2; B_ref[0][1][1]= 3;
        run_test(3'b000, 2, 2, 2, 1);

        for (test = 7; test < 207; test = test + 1) begin
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
            randomize_matrices(op, M, K, N, 1);
            run_test(op, M, K, N, 1);
        end

        test = 207;
        A_ref[0][0][0]=1; A_ref[0][0][1]=2;
        A_ref[0][1][0]=3; A_ref[0][1][1]=4;
        B_ref[0][0][0]=5; B_ref[0][0][1]=6;
        B_ref[0][1][0]=7; B_ref[0][1][1]=8;
        A_ref[1][0][0]=2; A_ref[1][0][1]=0;
        A_ref[1][1][0]=0; A_ref[1][1][1]=3;
        B_ref[1][0][0]=1; B_ref[1][0][1]=0;
        B_ref[1][1][0]=0; B_ref[1][1][1]=1;
        run_test(3'b000, 2, 2, 2, 2);

        test = 208;
        A_ref[0][0][0]=10; A_ref[0][0][1]=20;
        A_ref[0][1][0]=30; A_ref[0][1][1]=40;
        B_ref[0][0][0]=1;  B_ref[0][0][1]=2;
        B_ref[0][1][0]=3;  B_ref[0][1][1]=4;
        A_ref[1][0][0]=-5; A_ref[1][0][1]=15;
        A_ref[1][1][0]=25; A_ref[1][1][1]=-35;
        B_ref[1][0][0]=5;  B_ref[1][0][1]=-5;
        B_ref[1][1][0]=-5; B_ref[1][1][1]=5;
        run_test(3'b001, 2, 2, 2, 2);

        test = 209;
        A_ref[0][0][0]=3;  B_ref[0][0][0]=4;
        A_ref[1][0][0]=-2; B_ref[1][0][0]=5;
        A_ref[2][0][0]=7;  B_ref[2][0][0]=-3;
        run_test(3'b000, 1, 1, 1, 3);

        test = 210;
        A_ref[0][0][0]=1; A_ref[0][0][1]=2; A_ref[0][1][0]=3; A_ref[0][1][1]=4;
        B_ref[0][0][0]=4; B_ref[0][0][1]=3; B_ref[0][1][0]=2; B_ref[0][1][1]=1;
        A_ref[1][0][0]=5; A_ref[1][0][1]=6; A_ref[1][1][0]=7; A_ref[1][1][1]=8;
        B_ref[1][0][0]=8; B_ref[1][0][1]=7; B_ref[1][1][0]=6; B_ref[1][1][1]=5;
        A_ref[2][0][0]=-1; A_ref[2][0][1]=2;  A_ref[2][1][0]=-3; A_ref[2][1][1]=4;
        B_ref[2][0][0]=2;  B_ref[2][0][1]=-3; B_ref[2][1][0]=4;  B_ref[2][1][1]=-5;
        A_ref[3][0][0]=10; A_ref[3][0][1]=20; A_ref[3][1][0]=30; A_ref[3][1][1]=40;
        B_ref[3][0][0]=1;  B_ref[3][0][1]=1;  B_ref[3][1][0]=1;  B_ref[3][1][1]=1;
        run_test(3'b011, 2, 2, 2, 4);

        test = 211;
        A_ref[0][0][0]=1;  A_ref[0][0][1]=2;  A_ref[0][0][2]=3;
        A_ref[0][1][0]=4;  A_ref[0][1][1]=5;  A_ref[0][1][2]=6;
        A_ref[1][0][0]=7;  A_ref[1][0][1]=8;  A_ref[1][0][2]=9;
        A_ref[1][1][0]=10; A_ref[1][1][1]=11; A_ref[1][1][2]=12;
        run_test(3'b100, 2, 3, 3, 2);

        test = 212;
        A_ref[0][0][0]=1;  A_ref[0][0][1]=2;
        A_ref[0][1][0]=3;  A_ref[0][1][1]=4;
        A_ref[1][0][0]=10; A_ref[1][0][1]=20;
        A_ref[1][1][0]=30; A_ref[1][1][1]=40;
        run_test(3'b101, 2, 2, 2, 2);

        test = 213;
        A_ref[0][0][0]=100; A_ref[0][0][1]=200;
        A_ref[0][1][0]=300; A_ref[0][1][1]=400;
        B_ref[0][0][0]=1;   B_ref[0][0][1]=2;
        B_ref[0][1][0]=3;   B_ref[0][1][1]=4;
        A_ref[1][0][0]=-10; A_ref[1][0][1]=-20;
        A_ref[1][1][0]=-30; A_ref[1][1][1]=-40;
        B_ref[1][0][0]=-1;  B_ref[1][0][1]=-2;
        B_ref[1][1][0]=-3;  B_ref[1][1][1]=-4;
        A_ref[2][0][0]=0; A_ref[2][0][1]=0;
        A_ref[2][1][0]=0; A_ref[2][1][1]=0;
        B_ref[2][0][0]=0; B_ref[2][0][1]=0;
        B_ref[2][1][0]=0; B_ref[2][1][1]=0;
        run_test(3'b010, 2, 2, 2, 3);

        for (test = 214; test < 414; test = test + 1) begin
            M = DIM_W'($urandom_range(1, 4));
            K = DIM_W'($urandom_range(1, 4));
            N = DIM_W'($urandom_range(1, 4));
            D = DEP_W'($urandom_range(2, MAX_DEPTH));
            case ($urandom_range(0, 5))
                0: op = 3'b000;
                1: op = 3'b001;
                2: op = 3'b010;
                3: op = 3'b011;
                4: op = 3'b100;
                5: op = 3'b101;
            endcase
            randomize_matrices(op, M, K, N, D);
            run_test(op, M, K, N, D);
        end

        if (errors == 0)
            $display("\n*** ALL %0d TESTS PASSED ***\n", test);
        else
            $display("\n*** FAIL: %0d error(s) ***\n", errors);

        $finish;
    end

    initial begin
        #500_000_000;
        $display("WATCHDOG: simulation timeout");
        $finish;
    end

endmodule