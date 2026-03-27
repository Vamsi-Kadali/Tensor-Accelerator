`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.03.2026 14:59:44
// Design Name: 
// Module Name: accel_fsm
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


module accel_fsm (
    input clk,
    input rst,
    input start,
    input datapath_done,

    output reg en,
    output reg load,
    output reg busy,
    output reg done
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        INIT = 2'b01,
        RUN = 2'b10,
        DONE = 2'b11
    } state_t;

    state_t state, next_state;

    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        en    = 1'b0;
        load  = 1'b0;
        busy  = 1'b0;
        done  = 1'b0;
        next_state = state;

        case (state)

            IDLE: begin
                busy = 1'b0;
                if (start)
                    next_state = INIT;
            end

            INIT: begin
                busy = 1'b1;
                load = 1'b1;
                next_state = RUN;
            end
            
            RUN: begin
                busy = 1'b1;
                en = 1'b1;
                if (datapath_done)
                    next_state = DONE;
            end

            DONE: begin
                done = 1'b1;
                busy = 1'b0;
                next_state = IDLE;
            end

        endcase
    end

endmodule

module accel_top #( parameter WIDTH = 16, ACC = 40, N_MAX = 64, LANES = 64 )(
    input clk,
    input rst,
    input start,

    input [2:0] op,
    input [$clog2(N_MAX+1)-1:0] vec_len,

    input logic signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1],
    input logic signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1],

    output signed [ACC-1:0] res [0:LANES-1],
    output busy,
    output done
);

    wire en;
    wire load;
    wire datapath_done;

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

    simd_array #(WIDTH, ACC, N_MAX, LANES) simd (
        .clk(clk),
        .rst(rst),
        .load(load),
        .en(en),
        .op(op),
        .vec_len(vec_len),
        .a(a),
        .b(b),
        .res(res),
        .done(datapath_done)
    );

endmodule

module mac #( parameter WIDTH = 16, parameter ACC = 40 )(
    input  signed [WIDTH-1:0] a,
    input  signed [WIDTH-1:0] b,
    input  signed [ACC-1:0] acc_in,
    output signed [ACC-1:0] acc_out
);
    assign acc_out = acc_in + (a * b);
endmodule

module matrix_cont #(
    parameter WIDTH   = 16,
    parameter N_MAX   = 16,
    parameter LANES   = 8,
    parameter TILE_R  = 2,
    parameter TILE_C  = 4,
    parameter MAX_DIM = 16,
    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM),
    parameter ADDR_W  = $clog2(MAX_DIM*MAX_DIM)
)(
    input clk,
    input rst,
    input start,

    input [2:0] op,
    input [$clog2(MAX_DIM+1)-1:0] M_len,
    input [$clog2(MAX_DIM+1)-1:0] K_len,
    input [$clog2(MAX_DIM+1)-1:0] N_len,

    // BRAM interface
    output reg [ADDR_W-1:0] addr_a,
    output reg [ADDR_W-1:0] addr_b,
    output reg [ADDR_W-1:0] addr_c,

    input  signed [WIDTH-1:0] data_a,
    input  signed [WIDTH-1:0] data_b,

    output reg signed [ACC-1:0] data_c,
    output reg we_c,
    output [3:0] debug_state,
    output reg done
);

    //--------------------------------
    // Internal
    //--------------------------------
    reg accel_start;
    wire accel_done;
    
    reg signed [WIDTH-1:0] a_lane [0:LANES-1][0:N_MAX-1];
    reg signed [WIDTH-1:0] b_lane [0:LANES-1][0:N_MAX-1];
    wire signed [ACC-1:0] res [0:LANES-1];

    reg [$clog2(N_MAX+1)-1:0] vec_len;

    integer i, j, k_base;
    integer lane, row_idx, col_idx;
    integer r_off, c_off;

    reg [$clog2(N_MAX):0] load_k;
    reg [$clog2(LANES):0] load_lane;

    //--------------------------------
    // Accelerator
    //--------------------------------
    accel_top #(.WIDTH(WIDTH), .ACC(ACC), .N_MAX(N_MAX), .LANES(LANES)) accel (
        .clk(clk),
        .rst(rst),
        .start(accel_start),
        .op(op),
        .vec_len(vec_len),
        .a(a_lane),
        .b(b_lane),
        .res(res),
        .done(accel_done)
    );

    //--------------------------------
    // FSM
    //--------------------------------
    typedef enum logic [3:0] {
        IDLE,
        LOAD,
        START,
        WAIT,
        ACCUM,
        NEXT_K,
        NEXT_COL,
        NEXT_ROW,
        FINISH
    } state_t;

    state_t state;
    assign debug_state=state;
    //--------------------------------
    // lane mapping
    //--------------------------------
    function automatic void lane_to_rc(input int lane_idx, output int r, output int c);
        begin
            r = lane_idx / TILE_C;
            c = lane_idx % TILE_C;
        end
    endfunction

    //--------------------------------
    // FSM
    //--------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            accel_start <= 0;

            i <= 0; j <= 0; k_base <= 0;
            load_k <= 0; load_lane <= 0;
            we_c <= 0;
        end
        else begin
            case (state)

            //--------------------------------
            //IDLE
            //--------------------------------
            IDLE: begin
                done <= 0;
                accel_start <= 0;
                we_c <= 0;

                if (start) begin
                    i <= 0;
                    j <= 0;
                    k_base <= 0;
                    state <= LOAD;
                end
            end

            //--------------------------------
            //LOAD (SEQUENTIAL BRAM READ)
            //--------------------------------
            LOAD: begin
                we_c <= 0;

                // vec_len setup
                if (load_lane == 0 && load_k == 0) begin
                    if (op == 3'b000)
                        vec_len <= (K_len - k_base > N_MAX) ? N_MAX : (K_len - k_base);
                    else
                        vec_len <= 1;
                end

                if (load_lane < LANES) begin
                    lane_to_rc(load_lane, r_off, c_off);

                    row_idx = i + r_off;
                    col_idx = j + c_off;

                    // Address generation
                    addr_a <= row_idx * MAX_DIM + (k_base + load_k);
                    addr_b <= (k_base + load_k) * MAX_DIM + col_idx;

                    // Load into lane
                    a_lane[load_lane][load_k] <= data_a;
                    b_lane[load_lane][load_k] <= data_b;

                    // Iterate
                    if (load_k == vec_len - 1) begin
                        load_k <= 0;
                        load_lane <= load_lane + 1;
                    end else begin
                        load_k <= load_k + 1;
                    end
                end
                else begin
                    load_lane <= 0;
                    load_k <= 0;
                    state <= START;
                end
            end

            //--------------------------------
            //START
            //--------------------------------
            START: begin
                accel_start <= 1;
                state <= WAIT;
            end

            //--------------------------------
            //WAIT
            //--------------------------------
            WAIT: begin
                accel_start <= 0;
                if (accel_done)
                    state <= ACCUM;
            end

            //--------------------------------
            //ACCUM (WRITE BACK)
            //--------------------------------
            ACCUM: begin
                for (lane = 0; lane < LANES; lane = lane + 1) begin
                    lane_to_rc(lane, r_off, c_off);

                    row_idx = i + r_off;
                    col_idx = j + c_off;

                    if (row_idx < M_len && col_idx < N_len) begin
                        addr_c <= row_idx * MAX_DIM + col_idx;
                        data_c <= res[lane];
                        we_c   <= 1;
                    end
                end
                state <= NEXT_K;
            end

            //--------------------------------
            //NEXT_K
            //--------------------------------
            NEXT_K: begin
                we_c <= 0;

                if (k_base + vec_len < K_len) begin
                    k_base <= k_base + vec_len;
                    state <= LOAD;
                end else begin
                    k_base <= 0;
                    state <= NEXT_COL;
                end
            end

            //--------------------------------
            //NEXT_COL
            //--------------------------------
            NEXT_COL: begin
                if (j + TILE_C < N_len) begin
                    j <= j + TILE_C;
                    state <= LOAD;
                end else begin
                    state <= NEXT_ROW;
                end
            end

            //--------------------------------
            //NEXT_ROW
            //--------------------------------
            NEXT_ROW: begin
                if (i + TILE_R < M_len) begin
                    i <= i + TILE_R;
                    j <= 0;
                    state <= LOAD;
                end else begin
                    state <= FINISH;
                end
            end

            //--------------------------------
            //FINISH
            //--------------------------------
            FINISH: begin
                done <= 1;
                state <= IDLE;
            end

            endcase
        end
    end

endmodule

/*
    Balanced:       WIDTH   = 16
                    ACC     = 40
                    LANES   = 64
                    N_MAX   = 64
                    MAX_DIM = 256
                
    High Perf:      WIDTH   = 16
                    ACC     = 40
                    LANES   = 128
                    N_MAX   = 64
                    MAX_DIM = 256
                    
    Stress:         WIDTH   = 16
                    ACC     = 40
                    LANES   = 192
                    N_MAX   = 64
                    MAX_DIM = 256
*/

module simd_array #( parameter WIDTH = 16, ACC = 40, N_MAX = 64, LANES = 64 )(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,
    input [$clog2(N_MAX+1)-1:0] vec_len,

    input signed [WIDTH-1:0] a [0:LANES-1][0:N_MAX-1],
    input signed [WIDTH-1:0] b [0:LANES-1][0:N_MAX-1],

    output signed [ACC-1:0] res [0:LANES-1],
    output done
);

    wire [LANES-1:0] lane_done;

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : SIMD_LANES
            vector_lane #(WIDTH, ACC, N_MAX) lane (
                .clk(clk),
                .rst(rst),
                .load(load),
                .en(en),
                .op(op),
                .vec_len(vec_len),
                .a(a[i]),
                .b(b[i]),
                .res(res[i]),
                .done(lane_done[i])
            );
        end
    endgenerate

    assign done = &lane_done;

endmodule

module tensor_bram #(
    parameter WIDTH  = 16,
    parameter DEPTH  = 256,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input  clk,
 
    // Port A
    input  we_a,
    input  [ADDR_W-1:0]    addr_a,
    input  signed [WIDTH-1:0] din_a,
    output reg signed [WIDTH-1:0] dout_a,
 
    // Port B
    input  we_b,
    input  [ADDR_W-1:0]    addr_b,
    input  signed [WIDTH-1:0] din_b,
    output reg signed [WIDTH-1:0] dout_b
);
 
    (* ram_style = "block" *)
    reg signed [WIDTH-1:0] mem [0:DEPTH-1];
 
    // Port A - write/read
    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
    end
 
    // Port B - typically read-only in this design
    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end
 
endmodule

module tensor_top #(
    parameter WIDTH   = 16,
    parameter MAX_DIM = 16,

    parameter N_MAX   = 16,
    parameter LANES   = 8,
    parameter TILE_R  = 2,
    parameter TILE_C  = 4,

    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM),
    parameter DEPTH   = MAX_DIM * MAX_DIM,
    parameter ADDR_W  = $clog2(DEPTH)
)(
    input clk,
    input rst,
    input start,
    
    

    output done
);
    wire [3:0] debug_state;
    //-----------------------------------------
    // BRAM MEMORY (SYNTHESIZABLE)
    //-----------------------------------------
    reg [2:0] op = 3'b000;   // matrix multiply
    reg [4:0] M_len = 16;
    reg [4:0] K_len = 16;
    reg [4:0] N_len = 16;
    // A, B → read-only
    reg signed [WIDTH-1:0] A_mem [0:DEPTH-1];
    reg signed [WIDTH-1:0] B_mem [0:DEPTH-1];

    // C → write-back
    reg signed [ACC-1:0] C_mem [0:DEPTH-1];

    //-----------------------------------------
    // Internal BRAM interface signals
    //-----------------------------------------
    wire [ADDR_W-1:0] addr_a, addr_b, addr_c;
    wire signed [WIDTH-1:0] data_a, data_b;
    wire signed [ACC-1:0] data_c;
    wire we_c;
    ila_0 ila_inst (
    .clk(clk),

    .probe0(start),              // 1-bit 
    .probe1(done),               // 1-bit 

    .probe2(debug_state[3:0]),         // MUST be 4-bit

    .probe3(accel_start),        // 1-bit
    .probe4(accel_done),         // 1-bit

    .probe5(op[2:0]),            // MUST be 3-bit

    .probe6(M_len[4:0]),         // MUST be 5-bit
    .probe7(K_len[4:0]),         // MUST be 5-bit
    .probe8(N_len[4:0]),         // MUST be 5-bit

    .probe9(addr_a[7:0]),        // SLICE to 8-bit 
    .probe10(addr_b[7:0]),       // SLICE to 8-bit 
    .probe11(addr_c[7:0]),       // SLICE to 8-bit 

    .probe12(we_c),              // 1-bit

    .probe13({
    {4'b0, addr_a},
    {4'b0, addr_b},
    {4'b0, addr_c}
}) // 36-bit 
);
    //-----------------------------------------
    // BRAM READ (COMBINATIONAL)
    //-----------------------------------------
    assign data_a = A_mem[addr_a];
    assign data_b = B_mem[addr_b];

    //-----------------------------------------
    // BRAM WRITE (SEQUENTIAL)
    //-----------------------------------------
    always @(posedge clk) begin
        if (we_c) begin
            C_mem[addr_c] <= data_c;
        end
    end

    //-----------------------------------------
    // MATRIX CONTROLLER
    //-----------------------------------------
    matrix_cont #(
        .WIDTH(WIDTH),
        .N_MAX(N_MAX),
        .LANES(LANES),
        .TILE_R(TILE_R),
        .TILE_C(TILE_C),
        .MAX_DIM(MAX_DIM),
        .ACC(ACC)
    ) controller (

        .clk(clk),
        .rst(rst),
        .start(start),

        .op(op),
        .M_len(M_len),
        .K_len(K_len),
        .N_len(N_len),

        // BRAM interface
        .addr_a(addr_a),
        .addr_b(addr_b),
        .addr_c(addr_c),

        .data_a(data_a),
        .data_b(data_b),

        .data_c(data_c),
        .we_c(we_c),
        .debug_state(debug_state),
        .done(done)
    );

endmodule

module vector_lane #( parameter WIDTH = 16, ACC = 40, N_MAX = 64 )(
    input clk,
    input rst,
    input load,
    input en,

    input [2:0] op,

    input [$clog2(N_MAX+1)-1:0] vec_len,

    input signed [WIDTH-1:0] a [0:N_MAX-1],
    input signed [WIDTH-1:0] b [0:N_MAX-1],

    output reg signed [ACC-1:0] res,
    output reg done
);


    localparam ID_W = (N_MAX <= 1) ? 1 : $clog2(N_MAX);

    localparam
        OP_MATMULT = 3'b000,
        OP_ADD = 3'b001,
        OP_SUB = 3'b010,
        OP_HADAMARD = 3'b011,
        OP_ROW_ACCUM = 3'b100,
        OP_COL_ACCUM = 3'b101;


    reg [ID_W-1:0] id;

    reg signed [ACC-1:0] acc_reg;
    wire signed [ACC-1:0] acc_next;

    reg signed [WIDTH-1:0] a_reg [0:N_MAX-1];
    reg signed [WIDTH-1:0] b_reg [0:N_MAX-1];

    integer i;


    wire signed [WIDTH-1:0] a_sel = a_reg[id];
    wire signed [WIDTH-1:0] b_sel = b_reg[id];


    reg signed [WIDTH-1:0] a_eff;
    reg signed [WIDTH-1:0] b_eff;
    reg signed [ACC-1:0]   acc_eff;

    always @(*) begin
        a_eff = a_sel;
        b_eff = b_sel;
        acc_eff = acc_reg;

        case (op)
            OP_MATMULT: begin
            end

            OP_HADAMARD: begin
                acc_eff = 0;
            end

            OP_ADD: begin
                b_eff   = 1;
                acc_eff = b_sel;
            end

            OP_SUB: begin
                b_eff   = 1;
                acc_eff = -b_sel;
            end

            OP_ROW_ACCUM, OP_COL_ACCUM: begin
                b_eff = 1;
            end

            default: begin
                acc_eff = acc_reg;
            end
        endcase
    end

    mac #(WIDTH, ACC) mac_inst ( .a(a_eff), .b(b_eff), .acc_in(acc_eff), .acc_out(acc_next) );


    always @(posedge clk) begin
        if (rst) begin
            id <= '0;
            acc_reg <= '0;
            res <= '0;
            done <= 1'b0;

            for (i = 0; i < N_MAX; i = i + 1) begin
                a_reg[i] <= '0;
                b_reg[i] <= '0;
            end
        end

        else if (load) begin
            id <= '0;
            acc_reg <= '0;
            res <= '0;
            done <= 1'b0;

            for (i = 0; i < N_MAX; i = i + 1) begin
                if (i < vec_len) begin
                    a_reg[i] <= a[i];
                    b_reg[i] <= b[i];
                end
            end 
        end

        else if (en && !done && vec_len!=0) begin
            acc_reg <= acc_next;

            if (id == vec_len - 1) begin
                res <= acc_next;
                done <= 1'b1;
                id <= '0;
            end
            else begin
                id <= id + 1;
            end
        end
    end

endmodule
