`timescale 1ns / 1ps

module tb_tensor_top_bram_random;

    parameter WIDTH   = 16;
    parameter ACC     = 40;
    parameter MAX_DIM = 64;
    parameter DEPTH   = MAX_DIM*MAX_DIM;
    parameter ADDR_W  = $clog2(DEPTH);

    parameter TRACE_TEST = -1;

    reg clk;
    reg rst;
    reg start;
    reg [2:0] op;

    reg [$clog2(MAX_DIM+1)-1:0] M_len;
    reg [$clog2(MAX_DIM+1)-1:0] K_len;
    reg [$clog2(MAX_DIM+1)-1:0] N_len;

    wire done;

    reg we_a, we_b;
    reg [ADDR_W-1:0] addr_a, addr_b, addr_c;
    reg signed [WIDTH-1:0] din_a, din_b;
    wire signed [ACC-1:0] dout_c;

    reg signed [WIDTH-1:0] A [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [ACC-1:0]   GOLD [0:MAX_DIM-1][0:MAX_DIM-1];

    integer i, j, k, test;
    integer errors;
    reg signed [ACC-1:0] val;

    integer hadamard_mode;
    reg signed [WIDTH-1:0] scalar;
    reg signed [WIDTH-1:0] row_vec [0:MAX_DIM-1];
    reg signed [WIDTH-1:0] col_vec [0:MAX_DIM-1];

    integer prev_state;
    reg prev_use_internal_bram;
    reg prev_done;
    reg prev_start;
    reg prev_we_a;
    reg prev_we_b;
    reg prev_we_c;

    tensor_top #(
    .WIDTH(WIDTH),
    .MAX_DIM(MAX_DIM),
    .ACC(ACC),
    .DEPTH(DEPTH)
    ) DUT (
    .clk(clk),
    .rst(rst),
    .start(start),
    .op(op),
    .M_len(M_len),
    .K_len(K_len),
    .N_len(N_len),
    .we_a_ext(we_a),
    .we_b_ext(we_b),
    .addr_a_ext(addr_a),
    .addr_b_ext(addr_b),
    .din_a_ext(din_a),
    .din_b_ext(din_b),
    .addr_c_ext(addr_c),
    .dout_c_ext(dout_c),
    .done(done)
    );

    always #5 clk = ~clk;

    function automatic string state_name(input int s);
        begin
            case (s)
            0:  state_name = "IDLE";
            1:  state_name = "LOAD_A_ADDR";
            2:  state_name = "LOAD_A_WAIT";
            3:  state_name = "LOAD_A_STORE";
            4:  state_name = "LOAD_B_ADDR";
            5:  state_name = "LOAD_B_WAIT";
            6:  state_name = "LOAD_B_STORE";
            7:  state_name = "START";
            8:  state_name = "PAUSE";
            9:  state_name = "STORE_SETUP";
            10: state_name = "STORE_ARM";
            11: state_name = "STORE_COMMIT";
            12: state_name = "DONE";
            default: state_name = "UNK";
        endcase
    end
endfunction

task automatic dump_cycle(input string tag);
    begin
        $display("\n==================== %s ====================", tag);
        $display("time=%0t test=%0d op=%b M=%0d K=%0d N=%0d", $time, test, op, M_len, K_len, N_len);
        $display("TB : start=%0b done=%0b we_a=%0b addr_a=%0d din_a=%0d we_b=%0b addr_b=%0d din_b=%0d addr_c=%0d dout_c=%0d",
        start, done, we_a, addr_a, din_a, we_b, addr_b, din_b, addr_c, dout_c);

        $display("DUT: state=%0d(%s) use_internal_bram=%0b matrix_start=%0b matrix_done=%0b we_c=%0b",
        DUT.state, state_name(DUT.state), DUT.use_internal_bram, DUT.matrix_start, DUT.matrix_done, DUT.we_c);

        $display("DUT internal addrs: addr_a=%0d addr_b=%0d addr_c=%0d din_c=%0d",
        DUT.addr_a, DUT.addr_b, DUT.addr_c, DUT.din_c);

        $display("DUT internal outs : dout_a=%0d dout_b=%0d dout_c_int=%0d",
        DUT.dout_a, DUT.dout_b, DUT.dout_c_int);

        $display("DUT idx: i=%0d j=%0d", DUT.i, DUT.j);

        if (DUT.i >= 0 && DUT.i < MAX_DIM && DUT.j >= 0 && DUT.j < MAX_DIM) begin
            $display("DUT buffers @i,j: A_mat=%0d B_mat=%0d C_mat=%0d",
            DUT.A_mat[DUT.i][DUT.j],
            DUT.B_mat[DUT.i][DUT.j],
            DUT.C_mat[DUT.i][DUT.j]);
        end

        $display("BRAM @ internal addr_a: mem=%0d", DUT.bram_A.mem[DUT.addr_a]);
        $display("BRAM @ internal addr_b: mem=%0d", DUT.bram_B.mem[DUT.addr_b]);
        $display("BRAM @ internal addr_c: mem=%0d", DUT.bram_C.mem[DUT.addr_c]);

        $display("EXT addresses: addr_a_ext=%0d addr_b_ext=%0d addr_c_ext=%0d",
        addr_a, addr_b, addr_c);

        $display("EXT BRAM contents at ext addr: A=%0d B=%0d C=%0d",
        DUT.bram_A.mem[addr_a],
        DUT.bram_B.mem[addr_b],
        DUT.bram_C.mem[addr_c]);

        $display("================================================\n");
    end
endtask

task automatic dump_mismatch(input int row, input int col,
    input signed [ACC-1:0] got,
    input signed [ACC-1:0] exp);
    begin
        $display("\n************** MISMATCH **************");
        $display("test=%0d op=%b row=%0d col=%0d", test, op, row, col);
        $display("DUT=%0d  GOLD=%0d", got, exp);
        $display("compare addr=%0d", row*MAX_DIM + col);
        $display("BRAM_C[compare addr]=%0d", DUT.bram_C.mem[row*MAX_DIM + col]);
        dump_cycle("COMPARE_MISMATCH");
        $display("****************************************\n");
    end
endtask

always @(posedge clk) begin
    if (!rst && TRACE_TEST >= 0 && test == TRACE_TEST) begin
        if (DUT.state !== prev_state ||
        DUT.use_internal_bram !== prev_use_internal_bram ||
        done !== prev_done ||
        start !== prev_start ||
        we_a !== prev_we_a ||
        we_b !== prev_we_b ||
        DUT.we_c !== prev_we_c) begin
            dump_cycle("CYCLE_TRACE");
        end

        prev_state             = DUT.state;
        prev_use_internal_bram  = DUT.use_internal_bram;
        prev_done               = done;
        prev_start              = start;
        prev_we_a               = we_a;
        prev_we_b               = we_b;
        prev_we_c               = DUT.we_c;
    end
end

task automatic wait_idle;
    begin
        wait(DUT.use_internal_bram == 1'b0);
        @(posedge clk);
        @(posedge clk);
    end
endtask

task automatic write_A(input int addr_i, input signed [WIDTH-1:0] data);
    begin
        addr_a = addr_i;
        din_a  = data;
        we_a   = 1'b1;

        if (TRACE_TEST >= 0 && test == TRACE_TEST)
        $display("TB WRITE_A   t=%0t addr=%0d data=%0d", $time, addr_i, data);

        @(posedge clk);
        we_a = 1'b0;
    end
endtask

task automatic write_B(input int addr_i, input signed [WIDTH-1:0] data);
    begin
        addr_b = addr_i;
        din_b  = data;
        we_b   = 1'b1;

        if (TRACE_TEST >= 0 && test == TRACE_TEST)
        $display("TB WRITE_B   t=%0t addr=%0d data=%0d", $time, addr_i, data);

        @(posedge clk);
        we_b = 1'b0;
    end
endtask

task automatic read_C(input int addr_i, output signed [ACC-1:0] data);
    begin
        addr_c = addr_i;

        if (TRACE_TEST >= 0 && test == TRACE_TEST)
        $display("TB READ_C    t=%0t addr=%0d", $time, addr_i);

        @(posedge clk);
        @(posedge clk);
        data = dout_c;
    end
endtask

task automatic run;
    begin
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait(done);
        @(posedge clk);
        @(posedge clk);
    end
endtask

task automatic randomize_matrices;
    begin
        for (i = 0; i < MAX_DIM; i++)
        for (j = 0; j < MAX_DIM; j++) begin
            A[i][j] = 0;
            B[i][j] = 0;
            GOLD[i][j] = 0;
        end

        if (op == 3'b000 || op == 3'b100) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < K_len; j++)
            A[i][j] = $signed($urandom());

            for (i = 0; i < K_len; i++)
            for (j = 0; j < N_len; j++)
            B[i][j] = $signed($urandom());
        end
        else if (op == 3'b101) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++)
            A[i][j] = $signed($urandom());
        end
        else if (op == 3'b011) begin
            hadamard_mode = $urandom_range(0,3);

            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++)
            A[i][j] = $signed($urandom());

            case (hadamard_mode)
            0: begin
                for (i = 0; i < M_len; i++)
                for (j = 0; j < N_len; j++)
                B[i][j] = $signed($urandom());
            end

            1: begin
                scalar = $signed($urandom());
                for (i = 0; i < M_len; i++)
                for (j = 0; j < N_len; j++)
                B[i][j] = scalar;
            end

            2: begin
                for (j = 0; j < N_len; j++)
                row_vec[j] = $signed($urandom());

                for (i = 0; i < M_len; i++)
                for (j = 0; j < N_len; j++)
                B[i][j] = row_vec[j];
            end

            3: begin
                for (i = 0; i < M_len; i++)
                col_vec[i] = $signed($urandom());

                for (i = 0; i < M_len; i++)
                for (j = 0; j < N_len; j++)
                B[i][j] = col_vec[i];
            end
        endcase
    end
    else begin
        for (i = 0; i < M_len; i++)
        for (j = 0; j < N_len; j++) begin
            A[i][j] = $signed($urandom());
            B[i][j] = $signed($urandom());
        end
    end
end
endtask

task automatic load_bram;
    begin
        wait_idle();

        if (op == 3'b000) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < K_len; j++)
            write_A(i*MAX_DIM + j, A[i][j]);

            for (i = 0; i < K_len; i++)
            for (j = 0; j < N_len; j++)
            write_B(i*MAX_DIM + j, B[i][j]);
        end
        else if (op == 3'b100) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < K_len; j++)
            write_A(i*MAX_DIM + j, A[i][j]);
        end
        else if (op == 3'b101) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++)
            write_A(i*MAX_DIM + j, A[i][j]);
        end
        else begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++) begin
                write_A(i*MAX_DIM + j, A[i][j]);
                write_B(i*MAX_DIM + j, B[i][j]);
            end
        end
    end
endtask

task automatic compute_golden;
    begin
        for (i = 0; i < M_len; i++)
        for (j = 0; j < N_len; j++) begin
            GOLD[i][j] = 0;

            if (op == 3'b000)
            for (k = 0; k < K_len; k++)
            GOLD[i][j] += A[i][k] * B[k][j];

            else if (op == 3'b001)
            GOLD[i][j] = A[i][j] + B[i][j];

            else if (op == 3'b010)
            GOLD[i][j] = A[i][j] - B[i][j];

            else if (op == 3'b011)
            GOLD[i][j] = A[i][j] * B[i][j];

            else if (op == 3'b100)
            for (k = 0; k < K_len; k++)
            GOLD[i][j] += A[i][k];

            else if (op == 3'b101)
            for (k = 0; k < M_len; k++)
            GOLD[i][j] += A[k][j];
        end
    end
endtask

task automatic compare_result;
    begin
        for (i = 0; i < M_len; i++)
        for (j = 0; j < N_len; j++) begin
            read_C(i*MAX_DIM + j, val);

            if (val !== GOLD[i][j]) begin
                $display("ERROR TEST=%0d op=%b (%0d,%0d) DUT=%0d GOLD=%0d",
                test, op, i, j, val, GOLD[i][j]);
                errors++;
                dump_mismatch(i, j, val, GOLD[i][j]);
            end
        end
    end
endtask

initial begin
    clk   = 0;
    rst   = 1;
    start = 0;
    we_a  = 0;
    we_b  = 0;
    addr_a = 0;
    addr_b = 0;
    addr_c = 0;
    din_a  = 0;
    din_b  = 0;
    errors = 0;

    prev_state = -1;
    prev_use_internal_bram = 0;
    prev_done = 0;
    prev_start = 0;
    prev_we_a = 0;
    prev_we_b = 0;
    prev_we_c = 0;

    #20 rst = 0;
    @(posedge clk);
end

initial begin
    for (test = 0; test < 500; test++) begin

        M_len = $urandom_range(1,8);
        K_len = $urandom_range(1,8);
        N_len = $urandom_range(1,8);

        case ($urandom_range(0,5))
        0: op = 3'b000;
        1: op = 3'b001;
        2: op = 3'b010;
        3: op = 3'b011;
        4: op = 3'b100;
        5: op = 3'b101;
    endcase

    $display("\n=== TEST %0d op=%b M=%0d K=%0d N=%0d ===", test, op, M_len, K_len, N_len);

    randomize_matrices();
    load_bram();
    compute_golden();

    if (TRACE_TEST >= 0 && test == TRACE_TEST)
    dump_cycle("AFTER_LOAD_BEFORE_RUN");

    run();
    compare_result();

    $display("Test %0d complete", test);
end

if (errors == 0)
$display("\nALL PASSED\n");
else
$display("\nFAIL: %0d errors\n", errors);

$finish;
end

endmodule
