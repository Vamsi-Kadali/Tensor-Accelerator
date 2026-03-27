`timescale 1ns / 1ps

module tb_accel_top;

    parameter WIDTH = 16;
    parameter ACC   = 32;
    parameter N_MAX = 8;     // keep small for testing
    parameter LANES = 4;

    //-----------------------------------
    // DUT SIGNALS
    //-----------------------------------
    reg clk;
    reg rst;
    reg start;

    reg [2:0] op;
    reg [$clog2(N_MAX+1)-1:0] vec_len;

    // BRAM write interface
    reg we;
    reg [$clog2(N_MAX)-1:0] wr_addr;
    reg signed [WIDTH-1:0] a_wr [LANES];
    reg signed [WIDTH-1:0] b_wr [LANES];

    wire signed [ACC-1:0] res [LANES];
    wire busy;
    wire done;

    //-----------------------------------
    // DUT
    //-----------------------------------
    accel_top #(WIDTH, ACC, N_MAX, LANES) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .vec_len(vec_len),
        .we(we),
        .wr_addr(wr_addr),
        .a_wr(a_wr),
        .b_wr(b_wr),
        .res(res),
        .busy(busy),
        .done(done)
    );

    //-----------------------------------
    // CLOCK
    //-----------------------------------
    always #5 clk = ~clk;

    //-----------------------------------
    // TASK: WRITE VECTOR INTO BRAM
    //-----------------------------------
    task write_data;
        integer i, lane;
        begin
            we = 1;
            for (i = 0; i < vec_len; i = i + 1) begin
                wr_addr = i;

                for (lane = 0; lane < LANES; lane = lane + 1) begin
                    a_wr[lane] = i + lane + 1;   // simple pattern
                    b_wr[lane] = 1;              // dot with ones (sum)
                end

                @(posedge clk);
            end
            we = 0;
        end
    endtask

    //-----------------------------------
    // TEST SEQUENCE
    //-----------------------------------
    integer lane;

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        we = 0;

        op = 3'b000;        // MAC (dot product)
        vec_len = 4;

        #20;
        rst = 0;

        //-----------------------------------
        // LOAD DATA INTO BRAM
        //-----------------------------------
        write_data();

        //-----------------------------------
        // START COMPUTE
        //-----------------------------------
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        //-----------------------------------
        // WAIT FOR DONE
        //-----------------------------------
        wait(done);

        //-----------------------------------
        // DISPLAY RESULTS
        //-----------------------------------
        $display("==== RESULTS ====");
        for (lane = 0; lane < LANES; lane = lane + 1) begin
            $display("Lane %0d Result = %0d", lane, res[lane]);
        end

        //-----------------------------------
        // EXPECTED CHECK
        //-----------------------------------
        $display("==== EXPECTED ====");
        for (lane = 0; lane < LANES; lane = lane + 1) begin
            integer sum;
            integer i;

            sum = 0;
            for (i = 0; i < vec_len; i = i + 1)
                sum += (i + lane + 1);

            $display("Lane %0d Expected = %0d", lane, sum);
        end

        #20;
        $finish;
    end

endmodule