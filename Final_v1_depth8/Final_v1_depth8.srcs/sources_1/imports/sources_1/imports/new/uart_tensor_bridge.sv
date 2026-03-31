`timescale 1ns / 1ps

module uart_tensor_bridge #(
    parameter CLKS_PER_BIT = 868,

    parameter WIDTH     = 16,
    
    parameter MAX_DIM   = 64,
    parameter MAX_DEPTH = 8,
    
    parameter N_MAX     = 64,
    parameter LANES     = 64,
    
    parameter TILE_R    = 8,
    parameter TILE_C    = 8,
    parameter ACC       = 2*WIDTH + $clog2(MAX_DIM),
    parameter DEPTH     = MAX_DEPTH * MAX_DIM * MAX_DIM,
    parameter ADDR_W    = $clog2(DEPTH),
    parameter DIM_W     = $clog2(MAX_DIM + 1),
    parameter DEP_W     = $clog2(MAX_DEPTH + 1)
)(
    input  wire clk,
    input  wire rst_l,
    input  wire uart_rxd,
    output wire uart_txd
);

    localparam TX_BYTES = (ACC + 7) / 8;
    localparam TX_W     = TX_BYTES * 8;

    wire rst = ~rst_l;

    wire       rx_dv;
    wire [7:0] rx_byte;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .i_Rst      (rst),
        .i_Clock    (clk),
        .i_RX_Serial(uart_rxd),
        .o_RX_DV    (rx_dv),
        .o_RX_Byte  (rx_byte)
    );

    reg        tx_dv;
    reg  [7:0] tx_byte_r;
    wire       tx_done;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .i_Rst      (rst),
        .i_Clock    (clk),
        .i_TX_DV    (tx_dv),
        .i_TX_Byte  (tx_byte_r),
        .o_TX_Active(),
        .o_TX_Serial(uart_txd),
        .o_TX_Done  (tx_done)
    );

    reg  [2:0]              tt_op;
    reg  [DIM_W-1:0]        tt_M, tt_K, tt_N;
    reg  [DEP_W-1:0]        tt_D;
    reg                     tt_start;
    wire                    tt_done;

    reg                     we_a_ext;
    reg  [ADDR_W-1:0]       addr_a_ext;
    reg  signed [WIDTH-1:0] din_a_ext;

    reg                     we_b_ext;
    reg  [ADDR_W-1:0]       addr_b_ext;
    reg  signed [WIDTH-1:0] din_b_ext;

    reg  [ADDR_W-1:0]       addr_c_ext;
    wire signed [ACC-1:0]   dout_c_ext;

    tensor_top #(
        .WIDTH    (WIDTH),
        .MAX_DIM  (MAX_DIM),
        .MAX_DEPTH(MAX_DEPTH),
        .N_MAX    (N_MAX),
        .LANES    (LANES),
        .TILE_R   (TILE_R),
        .TILE_C   (TILE_C),
        .ACC      (ACC),
        .DEPTH    (DEPTH)
    ) u_tensor (
        .clk        (clk),
        .rst        (rst),
        .start      (tt_start),
        .op         (tt_op),
        .M_len      (tt_M),
        .K_len      (tt_K),
        .N_len      (tt_N),
        .D_len      (tt_D),
        .done       (tt_done),
        .we_a_ext   (we_a_ext),
        .addr_a_ext (addr_a_ext),
        .din_a_ext  (din_a_ext),
        .we_b_ext   (we_b_ext),
        .addr_b_ext (addr_b_ext),
        .din_b_ext  (din_b_ext),
        .addr_c_ext (addr_c_ext),
        .dout_c_ext (dout_c_ext)
    );

    reg  [7:0]                r_cmd;
    reg  [ADDR_W-1:0]         r_addr;
    reg  [WIDTH-1:0]          r_data;
    reg  [TX_W-1:0]           c_packed;
    reg  [$clog2(TX_BYTES):0] r_tx_idx;

    typedef enum logic [4:0] {
        IDLE,
        RECV_ADDR_HI,
        RECV_ADDR_LO,
        RECV_DATA_HI,
        RECV_DATA_LO,
        RECV_OP,
        RECV_M,
        RECV_K,
        RECV_N,
        RECV_D,
        WR_ISSUE,
        WR_DEASSERT,
        RUN_PULSE,
        RUN_WAIT,
        RD_ADDR,
        RD_WAIT,
        RD_SAMPLE,
        TX_LOAD,
        TX_WAIT
    } state_t;

    state_t state;

    function automatic [7:0] c_byte_sel (
        input [TX_W-1:0]           c,
        input [$clog2(TX_BYTES):0] idx
    );
        c_byte_sel = c[idx * 8 +: 8];
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            we_a_ext   <= 1'b0;
            we_b_ext   <= 1'b0;
            addr_a_ext <= '0;
            addr_b_ext <= '0;
            din_a_ext  <= '0;
            din_b_ext  <= '0;
            addr_c_ext <= '0;
            tt_start   <= 1'b0;
            tt_op      <= 3'b000;
            tt_M       <= '0;
            tt_K       <= '0;
            tt_N       <= '0;
            tt_D       <= '0;
            tx_dv      <= 1'b0;
            tx_byte_r  <= 8'h00;
            r_cmd      <= 8'h00;
            r_addr     <= '0;
            r_data     <= '0;
            c_packed   <= '0;
            r_tx_idx   <= '0;
        end else begin

            tt_start <= 1'b0;
            tx_dv    <= 1'b0;
            we_a_ext <= 1'b0;
            we_b_ext <= 1'b0;

            case (state)

            IDLE: begin
                if (rx_dv) begin
                    r_cmd <= rx_byte;
                    case (rx_byte)
                        8'h01:   state <= RECV_ADDR_HI;
                        8'h02:   state <= RECV_ADDR_HI;
                        8'h03:   state <= RECV_OP;
                        8'h04:   state <= RECV_ADDR_HI;
                        default: state <= IDLE;
                    endcase
                end
            end

            RECV_ADDR_HI: begin
                if (rx_dv) begin
                    r_addr[ADDR_W-1:8] <= rx_byte[ADDR_W-9:0];
                    state <= RECV_ADDR_LO;
                end
            end

            RECV_ADDR_LO: begin
                if (rx_dv) begin
                    r_addr[7:0] <= rx_byte;
                    case (r_cmd)
                        8'h01, 8'h02: state <= RECV_DATA_HI;
                        8'h04:        state <= RD_ADDR;
                        default:      state <= IDLE;
                    endcase
                end
            end

            RECV_DATA_HI: begin
                if (rx_dv) begin
                    r_data[15:8] <= rx_byte;
                    state <= RECV_DATA_LO;
                end
            end

            RECV_DATA_LO: begin
                if (rx_dv) begin
                    r_data[7:0] <= rx_byte;
                    state <= WR_ISSUE;
                end
            end

            WR_ISSUE: begin
                if (r_cmd == 8'h01) begin
                    we_a_ext   <= 1'b1;
                    addr_a_ext <= r_addr;
                    din_a_ext  <= r_data;
                end else begin
                    we_b_ext   <= 1'b1;
                    addr_b_ext <= r_addr;
                    din_b_ext  <= r_data;
                end
                state <= WR_DEASSERT;
            end

            WR_DEASSERT: begin
                tx_byte_r <= 8'hAA;
                tx_dv     <= 1'b1;
                r_tx_idx  <= '0;
                state     <= TX_WAIT;
            end

            RECV_OP: begin
                if (rx_dv) begin
                    tt_op <= rx_byte[2:0];
                    state <= RECV_M;
                end
            end

            RECV_M: begin
                if (rx_dv) begin
                    tt_M  <= rx_byte[DIM_W-1:0];
                    state <= RECV_K;
                end
            end

            RECV_K: begin
                if (rx_dv) begin
                    tt_K  <= rx_byte[DIM_W-1:0];
                    state <= RECV_N;
                end
            end

            RECV_N: begin
                if (rx_dv) begin
                    tt_N  <= rx_byte[DIM_W-1:0];
                    state <= RECV_D;
                end
            end

            RECV_D: begin
                if (rx_dv) begin
                    tt_D  <= rx_byte[DEP_W-1:0];
                    state <= RUN_PULSE;
                end
            end

            RUN_PULSE: begin
                tt_start <= 1'b1;
                state    <= RUN_WAIT;
            end

            RUN_WAIT: begin
                if (tt_done) begin
                    tx_byte_r <= 8'hAA;
                    tx_dv     <= 1'b1;
                    r_tx_idx  <= '0;
                    state     <= TX_WAIT;
                end
            end

            RD_ADDR: begin
                addr_c_ext <= r_addr;
                state      <= RD_WAIT;
            end

            RD_WAIT: begin
                state <= RD_SAMPLE;
            end

            RD_SAMPLE: begin
                c_packed <= {{(TX_W-ACC){dout_c_ext[ACC-1]}}, dout_c_ext};
                r_tx_idx <= TX_BYTES - 1;
                state    <= TX_LOAD;
            end

            TX_LOAD: begin
                tx_byte_r <= c_byte_sel(c_packed, r_tx_idx);
                tx_dv     <= 1'b1;
                state     <= TX_WAIT;
            end

            TX_WAIT: begin
                if (tx_done) begin
                    if (r_tx_idx == 0)
                        state <= IDLE;
                    else begin
                        r_tx_idx <= r_tx_idx - 1;
                        state    <= TX_LOAD;
                    end
                end
            end

            default: state <= IDLE;

            endcase
        end
    end

endmodule