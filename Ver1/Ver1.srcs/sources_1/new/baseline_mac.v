`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.02.2026 20:03:21
// Design Name: 
// Module Name: baseline_mac
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


module baseline_mac #( parameter WIDTH = 16, parameter ACC = 32, parameter N = 4)(
    input clk,
    input rst,
    input en,
    input signed [WIDTH-1:0] a [0:N-1],
    input signed [WIDTH-1:0] b [0:N-1],
    output reg signed [ACC-1:0] res,
    output reg done
    );
    
    localparam ID_W = (N <= 1) ? 1 : $clog2(N);
    
    reg [ID_W-1:0] id;
    reg signed [ACC-1:0] acc_reg;
    reg signed [ACC-1:0] acc_next;
    
    mac #(WIDTH, ACC) m1 (a[id], b[id], acc_reg, acc_next);
    
    always @(posedge clk) begin
        if (rst) begin
            id <= 0;
            acc_reg <= 0;
            res <= 0;
            done <= 0;
        end
        else if (en) begin
            acc_reg <= acc_next;

            if (id == N-1) begin
                res <= acc_next;
                done <= 1'b1;
                id <= 0;
            end
            
            else begin
                id <= id + 1;
                done <= 1'b0;
            end
        end
    end

endmodule


