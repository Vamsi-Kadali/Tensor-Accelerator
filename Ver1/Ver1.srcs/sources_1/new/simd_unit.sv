`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.03.2026 18:41:52
// Design Name: 
// Module Name: simd_unit
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


module simd_unit #( parameter WIDTH = 16, parameter ACC = 32, parameter N_MAX = 4, parameter LANES = 2 )(
    input clk,
    input rst,
    
    input start,
    input [$clog2(N_MAX+1)-1:0] vec_len,

    input signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1],
    input signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1],

    output signed [ACC-1:0] res [0:LANES-1],
    
    
    output busy,
    output done,
    
    input [1:0] op //NEW
);
    
    reg signed [WIDTH-1:0] a_sel [0:LANES-1][0:N_MAX-1]; //NEW
    reg signed [WIDTH-1:0] b_sel [0:LANES-1][0:N_MAX-1]; //NEW
    
    wire en;
    wire load;
    wire simd_done;

    accel_fsm fsm (
        .clk(clk),
        .rst(rst),
        .start(start),
        .datapath_done(simd_done),
        .en(en),
        .load(load),
        .busy(busy),
        .done(done)
    );

    simd_array #(
        .WIDTH(WIDTH),
        .ACC(ACC),
        .N_MAX(N_MAX),
        .LANES(LANES)
    ) simd (
        .clk(clk),
        .rst(rst),
        .load(load),
        .en(en),
        .vec_len(vec_len),
        .a(a_sel),
        .b(b_sel),
        .res(res),
        .done(simd_done)
    );
    
    //NEW
    localparam DOT = 2'b00, VEC_ADD = 2'b01, SCALAR_MUL = 2'b10;
    
    integer i, j;
    
    always @(*) begin
      for (i = 0; i < LANES; i = i + 1) begin
        for (j = 0; j < N_MAX; j = j + 1) begin
          case (op)
            DOT: begin
              a_sel[i][j] = a[i][j];
              b_sel[i][j] = b[i][j];
            end
    
            VEC_ADD: begin
              a_sel[i][j] = a[i][j];
              b_sel[i][j] = {{(WIDTH-1){1'b0}},1'b1};
            end
    
            SCALAR_MUL: begin
              a_sel[i][j] = a[i][j];
              b_sel[i][j] = b[i][0];
            end
    
            default: begin
              a_sel[i][j] = '0;
              b_sel[i][j] = '0;
            end
          endcase
        end
      end
    end
    
endmodule
