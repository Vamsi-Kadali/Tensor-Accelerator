`timescale 1ns / 1ps
// ============================================================
//  fpga_top  –  Artix-7 / Basys3 / Nexys A7
//
//  Pins (edit to match your XDC):
//    clk_in   → W5   (100 MHz oscillator)
//    rst      → active-high push-button (e.g. BTNC on Basys3)
//    uart_rxd → B18  (USB-UART RX from PC)
//    uart_txd → A18  (USB-UART TX to PC)
//
//  Parameters mirror the small defaults in tensor_top:
//    WIDTH=16  MAX_DIM=16  LANES=8  N_MAX=16  TILE_R=2  TILE_C=4
// ============================================================
module fpga_top (
    input  clk_in,
    input  rst,
    input  uart_rxd,
    output uart_txd
);

    // ── Parameters (keep in sync with tensor_top) ────────────
    localparam WIDTH   = 16;
    localparam MAX_DIM = 16;
    localparam N_MAX   = 16;
    localparam LANES   = 8;
    localparam TILE_R  = 2;
    localparam TILE_C  = 4;
    localparam ACC     = 2*WIDTH + $clog2(MAX_DIM);
    localparam DEPTH   = MAX_DIM * MAX_DIM;
    localparam ADDR_W  = $clog2(DEPTH);
    localparam ACC_BYTES = (ACC + 7) / 8;

    // ── Clock (100 MHz passthrough; add MMCM if you need PLL) ─
    wire clk;
    // For Basys3/Nexys A7 the on-board clock is already 100 MHz
    // Just use it directly (or instantiate BUFG if synthesis warns)
    assign clk = clk_in;

    // ── UART RX / TX ─────────────────────────────────────────
    wire [7:0] rx_data;
    wire       rx_valid;
    wire [7:0] tx_data;
    wire       tx_valid;
    wire       tx_ready;

    uart_rx #(
        .CLK_HZ (100_000_000),
        .BAUD   (115_200)
    ) u_rx (
        .clk     (clk),
        .rst     (rst),
        .rx      (uart_rxd),
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    uart_tx #(
        .CLK_HZ (100_000_000),
        .BAUD   (115_200)
    ) u_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_data (tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .tx      (uart_txd)
    );

    // ── tensor_top signals ────────────────────────────────────
    wire                    we_a_ext;
    wire [ADDR_W-1:0]       addr_a_ext;
    wire signed [WIDTH-1:0] din_a_ext;

    wire                    we_b_ext;
    wire [ADDR_W-1:0]       addr_b_ext;
    wire signed [WIDTH-1:0] din_b_ext;

    wire [ADDR_W-1:0]       addr_c_ext;
    wire signed [ACC-1:0]   dout_c_ext;

    wire [$clog2(MAX_DIM+1)-1:0] M_len, K_len, N_len;
    wire [2:0]  op;
    wire        tensor_start;
    wire        tensor_done;

    // ── UART Protocol Controller ──────────────────────────────
    uart_tensor_ctrl #(
        .WIDTH    (WIDTH),
        .MAX_DIM  (MAX_DIM),
        .ACC      (ACC),
        .DEPTH    (DEPTH),
        .ADDR_W   (ADDR_W),
        .ACC_BYTES(ACC_BYTES)
    ) u_ctrl (
        .clk       (clk),
        .rst       (rst),
        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .tx_data   (tx_data),
        .tx_valid  (tx_valid),
        .tx_ready  (tx_ready),
        .we_a_ext  (we_a_ext),
        .addr_a_ext(addr_a_ext),
        .din_a_ext (din_a_ext),
        .we_b_ext  (we_b_ext),
        .addr_b_ext(addr_b_ext),
        .din_b_ext (din_b_ext),
        .addr_c_ext(addr_c_ext),
        .dout_c_ext(dout_c_ext),
        .M_len     (M_len),
        .K_len     (K_len),
        .N_len     (N_len),
        .op        (op),
        .start     (tensor_start),
        .done      (tensor_done)
    );

    // ── Tensor Accelerator ────────────────────────────────────
    tensor_top #(
        .WIDTH  (WIDTH),
        .MAX_DIM(MAX_DIM),
        .N_MAX  (N_MAX),
        .LANES  (LANES),
        .TILE_R (TILE_R),
        .TILE_C (TILE_C)
    ) u_tensor (
        .clk       (clk),
        .rst       (rst),
        .start     (tensor_start),
        .op        (op),
        .M_len     (M_len),
        .K_len     (K_len),
        .N_len     (N_len),
        .we_a_ext  (we_a_ext),
        .addr_a_ext(addr_a_ext),
        .din_a_ext (din_a_ext),
        .we_b_ext  (we_b_ext),
        .addr_b_ext(addr_b_ext),
        .din_b_ext (din_b_ext),
        .addr_c_ext(addr_c_ext),
        .dout_c_ext(dout_c_ext),
        .done      (tensor_done)
    );

endmodule
