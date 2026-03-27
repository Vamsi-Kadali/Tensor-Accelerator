`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.03.2026 13:11:10
// Design Name: 
// Module Name: uart_tensor_bridge
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

`timescale 1ns / 1ps
// =============================================================================
//  uart_tensor_bridge.sv
//
//  Self-contained system: UART ↔ tensor_top.
//  Only four wires cross the module boundary:
//      clk, rst, uart_rxd (from host), uart_txd (to host)
//
//  tensor_top is instantiated INSIDE this module.  The bridge FSM drives its
//  external BRAM write ports (bram_A port-A, bram_B port-A), the read port
//  (bram_C port-B), and the start/op/M/K/N control signals directly.
//
//  ──────────────────────────────────────────────────────────────────────────
//  PACKET PROTOCOL  (host → FPGA, FPGA → host)
//  ──────────────────────────────────────────────────────────────────────────
//
//  WRITE_A  [0x01][addr(1B)][data_hi(1B)][data_lo(1B)]  → ACK 0xAA
//  WRITE_B  [0x02][addr(1B)][data_hi(1B)][data_lo(1B)]  → ACK 0xAA
//  RUN      [0x03][op(1B)] [M(1B)]  [K(1B)]  [N(1B)]   → ACK 0xAA  (after done)
//  READ_C   [0x04][addr(1B)]                            → TX_BYTES bytes, MSB first
//
//  addr      : flat BRAM index = row * MAX_DIM + col  (fits in ADDR_W bits)
//  data_hi/lo: 16-bit signed element, big-endian
//  op        : bits [2:0]  {000=MATMUL, 001=ADD, 010=SUB,
//                            011=HADAMARD, 100=ROW_ACCUM, 101=COL_ACCUM}
//  M/K/N     : dimension bytes (value 1 .. MAX_DIM each)
//  TX_BYTES  : ceil(ACC/8) bytes carrying the accumulator result, big-endian
//
//  ──────────────────────────────────────────────────────────────────────────
//  TIMING NOTES  (everything registered; all assignments non-blocking)
//  ──────────────────────────────────────────────────────────────────────────
//
//  BRAM write (tensor_top bram_A or bram_B, port A):
//    WR_ISSUE    : we<=1, addr, din scheduled via NB → live at next posedge
//    WR_DEASSERT : we=1 on wire → bram port-A fires mem[addr]<=din   ✓
//                  block-top default clears we=0 the same posedge     ✓
//
//  BRAM read (tensor_top bram_C, port B  - 1-cycle registered latency):
//    RD_ADDR   : addr_c_ext registered → live at next posedge
//    RD_WAIT   : BRAM samples addr, updates registered dout one cycle later
//    RD_SAMPLE : dout_c_ext valid → captured into r_c_data             ✓
//    (Identical to tensor_top's own LOAD_A_ADDR→LOAD_A_WAIT→LOAD_A_STORE)
//
//  tt_start pulse:
//    RUN_PULSE : tt_start<=1 → live on entry to RUN_WAIT (one posedge) ✓
//    block-top default then returns it to 0 immediately                 ✓
//
//  tt_done (one-cycle pulse from tensor_top's DONE state):
//    Sampled every cycle in RUN_WAIT → reliably caught                  ✓
//
// =============================================================================

module uart_tensor_bridge #(
    // ── UART baud-rate ────────────────────────────────────────────────────
    parameter CLKS_PER_BIT = 868,       // clk_freq / baud;  868 ≈ 100 MHz / 115200

    // ── tensor_top / BRAM sizing ──────────────────────────────────────────
    parameter WIDTH   = 16,
    parameter MAX_DIM = 16,
    parameter N_MAX   = 16,
    parameter LANES   = 8,
    parameter TILE_R  = 2,
    parameter TILE_C  = 4,
    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM),   // 36 for defaults above
    parameter DEPTH   = MAX_DIM * MAX_DIM,            // 256
    parameter ADDR_W  = $clog2(DEPTH),                // 8
    parameter DIM_W   = $clog2(MAX_DIM + 1)           // 5
)(
    input  wire clk,
    input  wire rst,         // synchronous, active-high

    input  wire uart_rxd,    // RX serial line (idle = 1)
    output wire uart_txd     // TX serial line (idle = 1)
);

    // =========================================================================
    // Derived constant
    // =========================================================================
    localparam TX_BYTES = (ACC + 7) / 8;    // bytes needed to transmit ACC bits

    // =========================================================================
    // UART RX instance
    // =========================================================================
    wire       rx_dv;
    wire [7:0] rx_byte;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .i_Rst_L    (~rst),          // uart_rx uses active-low reset
        .i_Clock    (clk),
        .i_RX_Serial(uart_rxd),
        .o_RX_DV    (rx_dv),
        .o_RX_Byte  (rx_byte)
    );

    // =========================================================================
    // UART TX instance
    // =========================================================================
    reg        tx_dv;
    reg  [7:0] tx_byte_r;
    wire       tx_done;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .i_Rst_L    (~rst),
        .i_Clock    (clk),
        .i_TX_DV    (tx_dv),
        .i_TX_Byte  (tx_byte_r),
        .o_TX_Active(),
        .o_TX_Serial(uart_txd),
        .o_TX_Done  (tx_done)
    );

    // =========================================================================
    // Internal nets: bridge FSM → tensor_top
    // =========================================================================

    // Control
    reg  [2:0]              tt_op;
    reg  [DIM_W-1:0]        tt_M, tt_K, tt_N;
    reg                     tt_start;
    wire                    tt_done;

    // bram_A port-A  (external write)
    reg                     we_a_ext;
    reg  [ADDR_W-1:0]       addr_a_ext;
    reg  signed [WIDTH-1:0] din_a_ext;

    // bram_B port-A  (external write)
    reg                     we_b_ext;
    reg  [ADDR_W-1:0]       addr_b_ext;
    reg  signed [WIDTH-1:0] din_b_ext;

    // bram_C port-B  (external read)
    reg  [ADDR_W-1:0]       addr_c_ext;
    wire signed [ACC-1:0]   dout_c_ext;

    // =========================================================================
    // tensor_top instance
    //   bram_A port-A  = bridge writes A elements
    //   bram_B port-A  = bridge writes B elements
    //   bram_C port-B  = bridge reads  C results
    //   bram_A/B port-B = tensor_top reads internally (driven by tensor_top FSM)
    //   bram_C port-A   = tensor_top writes results  (driven by tensor_top FSM)
    // =========================================================================
    tensor_top #(
        .WIDTH   (WIDTH),
        .MAX_DIM (MAX_DIM),
        .N_MAX   (N_MAX),
        .LANES   (LANES),
        .TILE_R  (TILE_R),
        .TILE_C  (TILE_C),
        .ACC     (ACC),
        .DEPTH   (DEPTH)
    ) u_tensor (
        .clk        (clk),
        .rst        (rst),
        // control
        .start      (tt_start),
        .op         (tt_op),
        .M_len      (tt_M),
        .K_len      (tt_K),
        .N_len      (tt_N),
        .done       (tt_done),
        // bram_A external write port
        .we_a_ext   (we_a_ext),
        .addr_a_ext (addr_a_ext),
        .din_a_ext  (din_a_ext),
        // bram_B external write port
        .we_b_ext   (we_b_ext),
        .addr_b_ext (addr_b_ext),
        .din_b_ext  (din_b_ext),
        // bram_C external read port
        .addr_c_ext (addr_c_ext),
        .dout_c_ext (dout_c_ext)
    );

    // =========================================================================
    // Bridge FSM registers
    // =========================================================================
    reg  [7:0]                  r_cmd;
    reg  [ADDR_W-1:0]           r_addr;
    reg  [WIDTH-1:0]            r_data;      // builds up: [15:8] then [7:0]
    reg  [ACC-1:0]              r_c_data;    // captured result for TX
    reg  [$clog2(TX_BYTES):0]   r_tx_idx;   // TX_BYTES-1 (MSB) … 0 (LSB)

    // =========================================================================
    // FSM state type
    // =========================================================================
    typedef enum logic [4:0] {
        IDLE,           // wait for command byte
        RECV_ADDR,      // 1-byte BRAM address
        RECV_DATA_HI,   // data[15:8]
        RECV_DATA_LO,   // data[7:0]  → WR_ISSUE
        RECV_OP,        // op byte
        RECV_M,
        RECV_K,
        RECV_N,         // → RUN_PULSE
        WR_ISSUE,       // register we/addr/din (live next posedge)
        WR_DEASSERT,    // BRAM writes on THIS posedge; clear we; send ACK
        RUN_PULSE,      // assert tt_start ONE cycle
        RUN_WAIT,       // wait for tt_done
        RD_ADDR,        // register addr_c_ext
        RD_WAIT,        // BRAM address pipeline (1 cycle latency)
        RD_SAMPLE,      // capture dout_c_ext
        TX_LOAD,        // put next byte on tx_byte_r, assert tx_dv
        TX_WAIT         // wait for tx_done; loop or return to IDLE
    } state_t;

    state_t state;

    // =========================================================================
    // Byte-select helper: picks byte [idx] from the ACC-wide result
    //   idx = TX_BYTES-1 → MSB byte,   idx = 0 → LSB byte
    // =========================================================================
    function automatic [7:0] c_byte_sel (
        input [ACC-1:0]            c,
        input [$clog2(TX_BYTES):0] idx
    );
        c_byte_sel = c[idx * 8 +: 8];
    endfunction

    // =========================================================================
    // Main FSM  (single synchronous always block, all non-blocking)
    // =========================================================================
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
            tx_dv      <= 1'b0;
            tx_byte_r  <= 8'h00;
            r_cmd      <= 8'h00;
            r_addr     <= '0;
            r_data     <= '0;
            r_c_data   <= '0;
            r_tx_idx   <= '0;
        end else begin

            //
            // ── Default: de-assert all single-cycle strobes ──────────────────
            // Each of these may be overridden further below in the case body.
            // In Verilog, the LAST non-blocking assignment in an always block
            // wins, so the case assignments below always take precedence.
            //
            tt_start <= 1'b0;
            tx_dv    <= 1'b0;
            we_a_ext <= 1'b0;
            we_b_ext <= 1'b0;

            case (state)

            // ── Wait for command byte ─────────────────────────────────────────
            IDLE: begin
                if (rx_dv) begin
                    r_cmd <= rx_byte;
                    case (rx_byte)
                        8'h01:   state <= RECV_ADDR;
                        8'h02:   state <= RECV_ADDR;
                        8'h03:   state <= RECV_OP;
                        8'h04:   state <= RECV_ADDR;
                        default: state <= IDLE;
                    endcase
                end
            end

            // ── 1-byte flat BRAM address ──────────────────────────────────────
            RECV_ADDR: begin
                if (rx_dv) begin
                    r_addr <= rx_byte[ADDR_W-1:0];
                    case (r_cmd)
                        8'h01, 8'h02: state <= RECV_DATA_HI;
                        8'h04:        state <= RD_ADDR;
                        default:      state <= IDLE;
                    endcase
                end
            end

            // ── Element high byte [15:8] ──────────────────────────────────────
            RECV_DATA_HI: begin
                if (rx_dv) begin
                    r_data[15:8] <= rx_byte;
                    state <= RECV_DATA_LO;
                end
            end

            // ── Element low byte [7:0]; r_data complete → write BRAM ──────────
            RECV_DATA_LO: begin
                if (rx_dv) begin
                    r_data[7:0] <= rx_byte;
                    state <= WR_ISSUE;
                end
            end

            // ── Drive we=1, addr, din (all take effect at next posedge) ───────
            //
            //   The block-top default sets we_a/b <= 0 first; these assignments
            //   come later in the same always block and therefore win (last NB
            //   assignment rule). On entry to WR_DEASSERT the outputs are live.
            //
            WR_ISSUE: begin
                if (r_cmd == 8'h01) begin
                    we_a_ext   <= 1'b1;
                    addr_a_ext <= r_addr;
                    din_a_ext  <= r_data;
                end else begin             // 8'h02 = WRITE_B
                    we_b_ext   <= 1'b1;
                    addr_b_ext <= r_addr;
                    din_b_ext  <= r_data;
                end
                state <= WR_DEASSERT;
            end

            // ── BRAM write fires on THIS posedge (we still 1 from WR_ISSUE). ──
            //   block-top has already scheduled we <= 0 (takes effect next cycle).
            //   Queue ACK byte for transmission.
            WR_DEASSERT: begin
                tx_byte_r <= 8'hAA;
                tx_dv     <= 1'b1;     // latch into uart_tx THIS cycle
                r_tx_idx  <= '0;       // single byte → idx=0 → IDLE after TX
                state     <= TX_WAIT;
            end

            // ── RUN: collect op / M / K / N ──────────────────────────────────
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
                    state <= RUN_PULSE;
                end
            end

            // ── Assert tt_start for exactly ONE posedge ───────────────────────
            //   tt_op/M/K/N are stable (latched in RECV_* states above).
            //   tt_start <= 1 is live at the start of RUN_WAIT.
            //   tensor_top IDLE samples start=1 → transitions to LOAD_A_ADDR.
            RUN_PULSE: begin
                tt_start <= 1'b1;
                state    <= RUN_WAIT;
            end

            // ── Block-top has cleared tt_start; tensor_top is computing. ──────
            //   tt_done pulses HIGH for exactly one clock (tensor_top DONE→IDLE).
            //   We sample it every cycle here, so it cannot be missed.
            RUN_WAIT: begin
                if (tt_done) begin
                    tx_byte_r <= 8'hAA;
                    tx_dv     <= 1'b1;
                    r_tx_idx  <= '0;
                    state     <= TX_WAIT;
                end
            end

            // ── READ_C: register address (live at next posedge) ───────────────
            RD_ADDR: begin
                addr_c_ext <= r_addr;
                state      <= RD_WAIT;
            end

            // ── addr_c_ext now live; bram_C samples it, output not ready yet ──
            RD_WAIT: begin
                state <= RD_SAMPLE;
            end

            // ── dout_c_ext is valid (registered BRAM output, 1-cycle latency) ─
            RD_SAMPLE: begin
                r_c_data <= dout_c_ext;
                r_tx_idx <= TX_BYTES - 1;   // start at MSB byte
                state    <= TX_LOAD;
            end

            // ── Present next byte to uart_tx ──────────────────────────────────
            TX_LOAD: begin
                tx_byte_r <= c_byte_sel(r_c_data, r_tx_idx);
                tx_dv     <= 1'b1;
                state     <= TX_WAIT;
            end

            // ── Wait for uart_tx to finish; repeat or return to IDLE ──────────
            //   ACK path  : r_tx_idx=0 → done after one byte → IDLE
            //   READ_C path: r_tx_idx counts TX_BYTES-1 down to 0 → IDLE
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
