`timescale 1ns / 1ps

module accel_top #(
    parameter WIDTH = 16,
    parameter ACC   = 32,
    parameter N_MAX = 4,
    parameter LANES = 4
)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic [2:0] op,
    input  logic scalar_en,
    input  logic [$clog2(N_MAX+1)-1:0] vec_len,

    output logic signed [ACC-1:0] res [LANES],
    output logic busy,
    output logic done
);



    logic en;
    logic load;
    logic datapath_done;



    logic signed [WIDTH-1:0] a_data [LANES];
    logic signed [WIDTH-1:0] b_data [LANES];

 

    logic [$clog2(N_MAX+1)-1:0] addr;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            addr <= 0;

        else if (load)
            addr <= 0;

        else if (en && addr < vec_len-1)
            addr <= addr + 1;
    end

  

    accel_fsm fsm (
        .clk(clk),
        .rst(rst),
        .start(start),
        .datapath_done(datapath_done),
        .en(en),
        .load(load),
        .busy(busy),
        .done(done)
    );

   

    genvar i;

    generate
        for (i = 0; i < LANES; i++) begin : BRAM_A

            (* ram_style = "block" *)
            logic signed [WIDTH-1:0] memA [0:N_MAX-1];

            always_ff @(posedge clk) begin
                a_data[i] <= memA[addr];
            end

        end
    endgenerate



    generate
        for (i = 0; i < LANES; i++) begin : BRAM_B

            (* ram_style = "block" *)
            logic signed [WIDTH-1:0] memB [0:N_MAX-1];

            always_ff @(posedge clk) begin
                b_data[i] <= memB[addr];
            end

        end
    endgenerate

-

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

        .op(op),
        .scalar_en(scalar_en),
        .vec_len(vec_len),

        .a(a_data),
        .b(b_data),

        .res(res),
        .done(datapath_done)
    );

endmodule
