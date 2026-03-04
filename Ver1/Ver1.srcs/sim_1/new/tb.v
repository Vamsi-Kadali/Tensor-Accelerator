`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.02.2026 20:24:58
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


module tb_simple;

    // Parameters
    localparam WIDTH = 16;
    localparam ACC   = 32;
    localparam N_MAX = 4;
    localparam LANES = 2;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst;
    reg start;
    reg [$clog2(N_MAX+1)-1:0] vec_len;
    reg [1:0] op;

    reg signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1];

    wire signed [ACC-1:0] res [0:LANES-1];
    wire busy;
    wire done;

    integer u, v;

    // DUT
    simd_unit #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .vec_len(vec_len),
        .a(a),
        .b(b),
        .res(res),
        .busy(busy),
        .done(done),
        .op(op)
    );

    // Simple procedure to set inputs
    task set_inputs(input logic signed [WIDTH-1:0] a_in[0:LANES-1][0:N_MAX-1],
                    input logic signed [WIDTH-1:0] b_in[0:LANES-1][0:N_MAX-1]);
        integer u=0, v=0;
        begin
            for (u=0;u<LANES;u=u+1)
                for (v=0;v<N_MAX;v=v+1) begin
                    a[u][v] = a_in[u][v];
                    b[u][v] = b_in[u][v];
                end
        end
    endtask

    // Test sequence
    initial begin
        rst = 1; start = 0; vec_len = N_MAX;
        #20 rst = 0;

        // ------------------------
        // DOT Product Example
        // ------------------------
        op = 2'b00; // DOT
        set_inputs('{ '{1,2,3,4}, '{2,3,4,5} },
                   '{ '{1,1,1,1}, '{1,1,1,1} } );
        start = 1;
        wait(done);
        $display("DOT Res: Lane0=%0d, Lane1=%0d (Expected: 1*1+2*2+3*3+4*4=30, 2*1+3*1+4*1+5*1=14)", res[0], res[1]);
        start = 0;

        // ------------------------
        // Vector Add Example
        // ------------------------
        #20;
        op = 2'b01; // VEC_ADD
        set_inputs('{ '{1,2,3,4}, '{5,6,7,8} },
                   '{ '{0,0,0,0}, '{0,0,0,0} } ); // b is ignored in vec_add
        start = 1;
        wait(done);
        $display("VEC_ADD Res: Lane0=%0d, Lane1=%0d (Expected: sum of ones = 4, sum of ones = 4)", res[0], res[1]);
        start = 0;

        // ------------------------
        // Scalar Multiply Example
        // ------------------------
        #20;
        op = 2'b10; // SCALAR_MUL
        set_inputs('{ '{1,2,3,4}, '{5,6,7,8} },
                   '{ '{2,0,0,0}, '{3,0,0,0} } ); // scalar in b[i][0]
        start = 1;
        wait(done);
        $display("SCALAR_MUL Res: Lane0=%0d, Lane1=%0d (Expected: 1*2+2*2+3*2+4*2=20, 5*3+6*3+7*3+8*3=78)", res[0], res[1]);
        start = 0;

        #50 $finish;
    end

endmodule