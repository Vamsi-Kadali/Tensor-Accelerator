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


`timescale 1ns / 1ps

module tb_tensor_top_fpga;

    parameter WIDTH   = 16;
    parameter ACC     = 40;
    parameter MAX_DIM = 64;
    parameter DEPTH   = MAX_DIM * MAX_DIM;
    parameter ADDR_W  = $clog2(DEPTH);

    reg clk, rst, start;
    reg [2:0] op;

    reg [$clog2(MAX_DIM+1)-1:0] M_len, K_len, N_len;

    // External BRAM interface
    reg we_a_ext, we_b_ext;
    reg [ADDR_W-1:0] addr_a_ext, addr_b_ext, addr_c_ext;
    reg signed [WIDTH-1:0] din_a_ext, din_b_ext;
    wire signed [ACC-1:0] dout_c_ext;

    wire done;

    // Local matrices
    reg signed [WIDTH-1:0] A [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [WIDTH-1:0] B [0:MAX_DIM-1][0:MAX_DIM-1];
    reg signed [ACC-1:0]   GOLD [0:MAX_DIM-1][0:MAX_DIM-1];

    integer i, j, k, test, errors;
    reg signed [ACC-1:0] val;

    //--------------------------------------
    // DUT
    //--------------------------------------
    tensor_top DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .M_len(M_len),
        .K_len(K_len),
        .N_len(N_len),

        .we_a_ext(we_a_ext),
        .addr_a_ext(addr_a_ext),
        .din_a_ext(din_a_ext),

        .we_b_ext(we_b_ext),
        .addr_b_ext(addr_b_ext),
        .din_b_ext(din_b_ext),

        .addr_c_ext(addr_c_ext),
        .dout_c_ext(dout_c_ext),

        .done(done)
    );

    always #5 clk = ~clk;

    //--------------------------------------
    // WRITE HELPERS (REAL BRAM STYLE)
    //--------------------------------------
    task write_A(input int addr, input signed [WIDTH-1:0] data);
    begin
        @(posedge clk);
        we_a_ext   <= 1;
        addr_a_ext <= addr;
        din_a_ext  <= data;
        @(posedge clk);
        we_a_ext   <= 0;
    end
    endtask

    task write_B(input int addr, input signed [WIDTH-1:0] data);
    begin
        @(posedge clk);
        we_b_ext   <= 1;
        addr_b_ext <= addr;
        din_b_ext  <= data;
        @(posedge clk);
        we_b_ext   <= 0;
    end
    endtask

    //--------------------------------------
    // READ HELPER (1-cycle latency)
    //--------------------------------------
    task read_C(input int addr, output signed [ACC-1:0] data);
    begin
        @(posedge clk);
        addr_c_ext <= addr;
        @(posedge clk); // BRAM latency
        data = dout_c_ext;
    end
    endtask

    //--------------------------------------
    // RUN
    //--------------------------------------
    task run;
    begin
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        wait(done);
        @(posedge clk);
    end
    endtask

    //--------------------------------------
    // RANDOMIZE
    //--------------------------------------
    task randomize_matrices;
    begin
        for (i = 0; i < MAX_DIM; i++)
        for (j = 0; j < MAX_DIM; j++) begin
            A[i][j] = 0;
            B[i][j] = 0;
            GOLD[i][j] = 0;
        end

        for (i = 0; i < M_len; i++)
        for (j = 0; j < N_len; j++) begin
            A[i][j] = $signed($urandom());
            B[i][j] = $signed($urandom());
        end
    end
    endtask

    //--------------------------------------
    // LOAD TO BRAM (REALISTIC)
    //--------------------------------------
    task load_to_bram;
    begin
        if (op == 3'b000 || op == 3'b100) begin
            for (i = 0; i < M_len; i++)
            for (j = 0; j < K_len; j++)
                write_A(i*MAX_DIM + j, A[i][j]);

            for (i = 0; i < K_len; i++)
            for (j = 0; j < N_len; j++)
                write_B(i*MAX_DIM + j, B[i][j]);
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

    //--------------------------------------
    // GOLDEN
    //--------------------------------------
    task compute_golden;
    begin
        for (i = 0; i < M_len; i++)
        for (j = 0; j < N_len; j++) begin
            GOLD[i][j] = 0;

            case (op)
                3'b000: for (k = 0; k < K_len; k++) GOLD[i][j] += A[i][k] * B[k][j];
                3'b001: GOLD[i][j] = A[i][j] + B[i][j];
                3'b010: GOLD[i][j] = A[i][j] - B[i][j];
                3'b011: GOLD[i][j] = A[i][j] * B[i][j];
                3'b100: for (k = 0; k < K_len; k++) GOLD[i][j] += A[i][k];
                3'b101: for (k = 0; k < M_len; k++) GOLD[i][j] += A[k][j];
            endcase
        end
    end
    endtask

    //--------------------------------------
    // COMPARE
    //--------------------------------------
    task compare_result;
    begin
        for (i = 0; i < M_len; i++)
        for (j = 0; j < N_len; j++) begin
            read_C(i*MAX_DIM + j, val);

            if (val !== GOLD[i][j]) begin
                $display("ERROR (%0d,%0d): DUT=%0d GOLD=%0d", i, j, val, GOLD[i][j]);
                errors++;
            end
        end
    end
    endtask

    //--------------------------------------
    // MAIN
    //--------------------------------------
    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        we_a_ext = 0;
        we_b_ext = 0;
        errors = 0;

        #20 rst = 0;

        for (test = 0; test < 100; test++) begin
            M_len = $urandom_range(1, 8);
            K_len = $urandom_range(1, 8);
            N_len = $urandom_range(1, 8);
            op    = $urandom_range(0,5);

            randomize_matrices();
            load_to_bram();
            compute_golden();
            run();
            compare_result();

            $display("Test %0d done", test);
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAIL: %0d errors", errors);

        $finish;
    end

endmodule