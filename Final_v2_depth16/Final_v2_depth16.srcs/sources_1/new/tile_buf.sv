`timescale 1ns / 1ps

module tile_buf #(
    parameter WIDTH = 16,
    parameter DEPTH = 64
)(
    input                      clk,

    input                      we,
    input  [$clog2(DEPTH)-1:0] waddr,
    input  signed [WIDTH-1:0]  wdata,

    input  [$clog2(DEPTH)-1:0] raddr,
    output signed [WIDTH-1:0]  rdata
);

    (* ram_style = "distributed" *) reg signed [WIDTH-1:0] mem [0:DEPTH-1];

    reg                      we_r;
    reg [$clog2(DEPTH)-1:0]  waddr_r;
    reg signed [WIDTH-1:0]   wdata_r;

    always @(posedge clk) begin
        we_r    <= we;
        waddr_r <= waddr;
        wdata_r <= wdata;
    end

    always @(posedge clk) begin
        if (we_r)
            mem[waddr_r] <= wdata_r;
    end

    assign rdata = mem[raddr];

endmodule