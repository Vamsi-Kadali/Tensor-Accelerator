`timescale 1ns / 1ps

module tile_buf #(
    parameter WIDTH = 16,
    parameter DEPTH = 64
)(
    input                           clk,

    input                           we,
    input  [$clog2(DEPTH)-1:0]      waddr,
    input  signed [WIDTH-1:0]       wdata,

    input  [$clog2(DEPTH)-1:0]      raddr,
    output signed [WIDTH-1:0]       rdata
);

    (* ram_style = "distributed" *) reg signed [WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    assign rdata = mem[raddr];

endmodule