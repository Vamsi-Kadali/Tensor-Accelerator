`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.03.2026 18:40:17
// Design Name: 
// Module Name: tb_BRAM
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



module tb_tensor_top_bram_random;

    parameter WIDTH   = 16;
    parameter ACC     = 40;
    parameter MAX_DIM = 64;
    parameter DEPTH   = MAX_DIM*MAX_DIM;

    reg clk;
    reg rst;
    reg start;
    reg [2:0] op;

    reg [$clog2(MAX_DIM+1)-1:0] M_len;
    reg [$clog2(MAX_DIM+1)-1:0] K_len;
    reg [$clog2(MAX_DIM+1)-1:0] N_len;

    wire done;

    // Local matrices
    reg signed [WIDTH-1:0] A [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [ACC-1:0]   GOLD [0:MAX_DIM-1][0:MAX_DIM-1];

    integer i, j, k, test;
    integer errors;
    reg signed [ACC-1:0] val;

    // Hadamard helpers
    integer hadamard_mode;
    reg signed [WIDTH-1:0] scalar;
    reg signed [WIDTH-1:0] row_vec [0:MAX_DIM-1];
    reg signed [WIDTH-1:0] col_vec [0:MAX_DIM-1];

    //--------------------------------------------------
    // DUT
    //--------------------------------------------------
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
        .done(done)
    );

    always #5 clk = ~clk;

    //--------------------------------------------------
    // BRAM ACCESS
    //--------------------------------------------------
    task automatic clear_bram;
        begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                DUT.bram_A.mem[i] = 0;
                DUT.bram_B.mem[i] = 0;
                DUT.bram_C.mem[i] = 0;
            end
        end
    endtask

    task automatic write_A(input int addr, input signed [WIDTH-1:0] data);
        DUT.bram_A.mem[addr] = data;
    endtask

    task automatic write_B(input int addr, input signed [WIDTH-1:0] data);
        DUT.bram_B.mem[addr] = data;
    endtask

    function automatic signed [ACC-1:0] read_C(input int addr);
        read_C = DUT.bram_C.mem[addr];
    endfunction

    //--------------------------------------------------
    // RUN
    //--------------------------------------------------
    task automatic run;
        begin
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;
            wait(done);
            @(posedge clk);
        end
    endtask

    //--------------------------------------------------
    // RANDOMIZE
    //--------------------------------------------------
    task automatic randomize_matrices;
    begin
        // Clear
        for (i = 0; i < MAX_DIM; i++)
        for (j = 0; j < MAX_DIM; j++) begin
            A[i][j] = 0;
            B[i][j] = 0;
            GOLD[i][j] = 0;
        end

        //--------------------------------
        // MATMUL / ROW_ACCUM
        //--------------------------------
        if (op == 3'b000 || op == 3'b100) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < K_len; j++)
                A[i][j] = $signed($urandom());

            for (i = 0; i < K_len; i++)
            for (j = 0; j < N_len; j++)
                B[i][j] = $signed($urandom());
        end

        //--------------------------------
        // COLUMN ACCUM
        //--------------------------------
        else if (op == 3'b101) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++)
                A[i][j] = $signed($urandom());
        end

        //--------------------------------
        // HADAMARD (ALL MODES)
        //--------------------------------
        else if (op == 3'b011) begin

            hadamard_mode = $urandom_range(0,3);

            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++)
                A[i][j] = $signed($urandom());

            case (hadamard_mode)

            // tensor ⊙ tensor
            0: begin
                for (i = 0; i < M_len; i++)
                for (j = 0; j < N_len; j++)
                    B[i][j] = $signed($urandom());
            end

            // scalar broadcast
            1: begin
                scalar = $signed($urandom());
                for (i = 0; i < M_len; i++)
                for (j = 0; j < N_len; j++)
                    B[i][j] = scalar;
            end

            // row broadcast
            2: begin
                for (j = 0; j < N_len; j++)
                    row_vec[j] = $signed($urandom());

                for (i = 0; i < M_len; i++)
                for (j = 0; j < N_len; j++)
                    B[i][j] = row_vec[j];
            end

            // column broadcast
            3: begin
                for (i = 0; i < M_len; i++)
                    col_vec[i] = $signed($urandom());

                for (i = 0; i < M_len; i++)
                for (j = 0; j < N_len; j++)
                    B[i][j] = col_vec[i];
            end

            endcase
        end

        //--------------------------------
        // ADD / SUB
        //--------------------------------
        else begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++) begin
                A[i][j] = $signed($urandom());
                B[i][j] = $signed($urandom());
            end
        end
    end
    endtask

    //--------------------------------------------------
    // LOAD BRAM
    //--------------------------------------------------
    task automatic load_to_bram;
    begin
        clear_bram();

        if (op == 3'b000 || op == 3'b100) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < K_len; j++)
                write_A(i*MAX_DIM + j, A[i][j]);

            for (i = 0; i < K_len; i++)
            for (j = 0; j < N_len; j++)
                write_B(i*MAX_DIM + j, B[i][j]);
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

    //--------------------------------------------------
    // GOLDEN
    //--------------------------------------------------
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

    //--------------------------------------------------
    // COMPARE
    //--------------------------------------------------
    task automatic compare_result;
    begin
        for (i = 0; i < M_len; i++)
        for (j = 0; j < N_len; j++) begin
            val = read_C(i*MAX_DIM + j);
            if (val !== GOLD[i][j]) begin
                $display("ERROR TEST=%0d op=%b (%0d,%0d) DUT=%0d GOLD=%0d",
                         test, op, i, j, val, GOLD[i][j]);
                errors++;
            end
        end
    end
    endtask

    //--------------------------------------------------
    // MAIN
    //--------------------------------------------------
    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        errors = 0;

        #20 rst = 0;

        for (test = 0; test < 500; test++) begin

            M_len = $urandom_range(1,10);
            K_len = $urandom_range(1,10);
            N_len = $urandom_range(1,10);

            case ($urandom_range(0,5))
                0: op = 3'b000;
                1: op = 3'b001;
                2: op = 3'b010;
                3: op = 3'b011;
                4: op = 3'b100;
                5: op = 3'b101;
            endcase

            randomize_matrices();
            load_to_bram();
            compute_golden();
            run();
            compare_result();

            $display("Test %0d complete (op=%b)", test, op);
        end

        if (errors == 0)
            $display("\nALL TESTS PASSED\n");
        else
            $display("\nFAIL: %0d errors\n", errors);

        $finish;
    end

endmodule