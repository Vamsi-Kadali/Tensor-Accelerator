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
    parameter DEPTH   = MAX_DIM * MAX_DIM;
    parameter ADDR_W  = $clog2(DEPTH);

    reg clk;
    reg rst;
    reg start;
    reg [2:0] op;

    reg [$clog2(MAX_DIM+1)-1:0] M_len;
    reg [$clog2(MAX_DIM+1)-1:0] K_len;
    reg [$clog2(MAX_DIM+1)-1:0] N_len;

    wire done;

    // ----------------------------------------------------------------
    // External BRAM port signals (now actively driven by the testbench)
    // ----------------------------------------------------------------
    reg we_a_ext;
    reg we_b_ext;
    reg [ADDR_W-1:0] addr_a_ext;
    reg [ADDR_W-1:0] addr_b_ext;
    reg signed [WIDTH-1:0] din_a_ext;
    reg signed [WIDTH-1:0] din_b_ext;
    reg [ADDR_W-1:0] addr_c_ext;
    wire signed [ACC-1:0] dout_c_ext;

    // Local matrices
    reg signed [WIDTH-1:0] A    [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B    [0:MAX_DIM-1][0:MAX_DIM-1];
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
        .WIDTH  (WIDTH),
        .MAX_DIM(MAX_DIM),
        .ACC    (ACC),
        .DEPTH  (DEPTH)
    ) DUT (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .op        (op),
        .M_len     (M_len),
        .K_len     (K_len),
        .N_len     (N_len),
        .we_a_ext  (we_a_ext),
        .addr_a_ext(addr_a_ext),
        .din_a_ext (din_a_ext),
        .we_b_ext  (we_b_ext),
        .addr_b_ext(addr_b_ext),
        .din_b_ext (din_b_ext),
        .addr_c_ext(addr_c_ext),
        .dout_c_ext(dout_c_ext),
        .done      (done)
    );

    always #5 clk = ~clk;

    //--------------------------------------------------
    // BUS IDLE
    //--------------------------------------------------
    task automatic idle_ext_bus;
    begin
        we_a_ext   = 1'b0;
        we_b_ext   = 1'b0;
        addr_a_ext = '0;
        addr_b_ext = '0;
        din_a_ext  = '0;
        din_b_ext  = '0;
        addr_c_ext = '0;
    end
    endtask

    //--------------------------------------------------
    // BRAM WRITE HELPERS (synchronous writes)
    // Drive address/data before the rising edge, then hold through it.
    //--------------------------------------------------
    task automatic write_A(input int addr_i, input signed [WIDTH-1:0] data);
    begin
        @(negedge clk);
        we_a_ext   = 1'b1;
        addr_a_ext = addr_i[ADDR_W-1:0];
        din_a_ext  = data;
        @(posedge clk);
        @(negedge clk);
        we_a_ext   = 1'b0;
    end
    endtask

    task automatic write_B(input int addr_i, input signed [WIDTH-1:0] data);
    begin
        @(negedge clk);
        we_b_ext   = 1'b1;
        addr_b_ext = addr_i[ADDR_W-1:0];
        din_b_ext  = data;
        @(posedge clk);
        @(negedge clk);
        we_b_ext   = 1'b0;
    end
    endtask

    //--------------------------------------------------
    // BRAM READ HELPER (synchronous read on port B of bram_C)
    // IMPORTANT: sample dout_c_ext after a small delay after posedge
    // so we do not race the nonblocking assignment inside the BRAM.
    //--------------------------------------------------
    task automatic read_C(input int addr_i, output signed [ACC-1:0] data);
    begin
        @(negedge clk);
        addr_c_ext = addr_i[ADDR_W-1:0];
        @(posedge clk);
        #1;
        data = dout_c_ext;
    end
    endtask

    //--------------------------------------------------
    // RUN
    //--------------------------------------------------
    task automatic run;
    begin
        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        start = 1'b0;

        wait(done === 1'b1);
        @(posedge clk);
        #1;
    end
    endtask

    //--------------------------------------------------
    // RANDOMIZE
    //--------------------------------------------------
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
            hadamard_mode = $urandom_range(0, 3);

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

    //--------------------------------------------------
    // LOAD BRAM USING TENSOR_TOP INPUT PORTS
    //--------------------------------------------------
    task automatic load_to_bram;
    begin
        // Ensure no accidental writes while loading
        idle_ext_bus();

        if (op == 3'b000 || op == 3'b100) begin
            // Matmul / row accumulation: load A
            for (i = 0; i < M_len; i++)
            for (j = 0; j < K_len; j++)
                write_A(i * MAX_DIM + j, A[i][j]);

            // Matmul only: load B
            if (op == 3'b000) begin
                for (i = 0; i < K_len; i++)
                for (j = 0; j < N_len; j++)
                    write_B(i * MAX_DIM + j, B[i][j]);
            end
        end
        else if (op == 3'b101) begin
            // Column accumulation: only A is needed
            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++)
                write_A(i * MAX_DIM + j, A[i][j]);
        end
        else begin
            // Add / Sub / Hadamard: load both matrices
            for (i = 0; i < M_len; i++)
            for (j = 0; j < N_len; j++) begin
                write_A(i * MAX_DIM + j, A[i][j]);
                write_B(i * MAX_DIM + j, B[i][j]);
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
            if      (op == 3'b000) for (k = 0; k < K_len; k++) GOLD[i][j] += A[i][k] * B[k][j];
            else if (op == 3'b001) GOLD[i][j] = A[i][j] + B[i][j];
            else if (op == 3'b010) GOLD[i][j] = A[i][j] - B[i][j];
            else if (op == 3'b011) GOLD[i][j] = A[i][j] * B[i][j];
            else if (op == 3'b100) for (k = 0; k < K_len; k++) GOLD[i][j] += A[i][k];
            else if (op == 3'b101) for (k = 0; k < M_len; k++) GOLD[i][j] += A[k][j];
        end
    end
    endtask

    //--------------------------------------------------
    // COMPARE RESULTS USING EXTERNAL READ PORT OF C
    //--------------------------------------------------
    task automatic compare_result;
    begin
        for (i = 0; i < M_len; i++)
        for (j = 0; j < N_len; j++) begin
            read_C(i * MAX_DIM + j, val);

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
        clk    = 0;
        rst    = 1;
        start  = 0;
        errors = 0;
        idle_ext_bus();

        #20 rst = 0;
        @(posedge clk);

        for (test = 0; test < 500; test++) begin
            M_len = $urandom_range(1, 10);
            K_len = $urandom_range(1, 10);
            N_len = $urandom_range(1, 10);

            case ($urandom_range(0, 5))
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