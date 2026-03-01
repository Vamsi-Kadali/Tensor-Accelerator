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


module baseline_mac #( parameter WIDTH = 16, parameter ACC = 32, parameter N_MAX = 4)(
    input clk,
    input rst,
    input load,
    input en,
    
    input [$clog2(N_MAX+1)-1:0] vec_len,
    
    input signed [WIDTH-1:0] a [0:N_MAX-1],
    input signed [WIDTH-1:0] b [0:N_MAX-1],
    
    output reg signed [ACC-1:0] res,
    output reg done
    );
    
    localparam ID_W = (N_MAX <= 1) ? 1 : $clog2(N_MAX);
    
    reg [ID_W-1:0] id;
    reg signed [ACC-1:0] acc_reg;
    reg signed [ACC-1:0] acc_next;
    
    reg signed [WIDTH-1:0] a_reg [0:N_MAX-1];
    reg signed [WIDTH-1:0] b_reg [0:N_MAX-1];
    integer i;
    
    mac #(WIDTH, ACC) m1 (a_reg[id], b_reg[id], acc_reg, acc_next);
    
    always @(posedge clk) begin
        if (rst) begin
            id <= 1'b0;
            acc_reg <= 1'b0;
            res <= 1'b0;
            done <= 1'b0;
            for (i = 0; i < N_MAX; i = i + 1) begin a_reg[i] <= 1'b0; b_reg[i] <= 1'b0; end
        end
        
        else if (load) begin
            id <= 1'b0;
            acc_reg <= 1'b0;
            res <= 1'b0;
            done <= 1'b0;            
            a_reg <= a;
            b_reg <= b;
        end
            
        else if (en && !done) begin
            acc_reg <= acc_next;

            if (id == vec_len-1) begin
                res <= acc_next;
                done <= 1'b1;
                id <= 1'b0;
            end
            
            else begin
                id <= id + 1;
            end
        end
    end

endmodule




