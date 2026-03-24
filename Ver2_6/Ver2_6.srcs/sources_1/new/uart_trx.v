`timescale 1ns / 1ps
// ============================================================
//  uart_rx  –  8N1, 100 MHz clock, 115200 baud
//  Outputs one byte on (rx_data, rx_valid) for one cycle.
// ============================================================
module uart_rx #(
    parameter CLK_HZ  = 100_000_000,
    parameter BAUD    = 115_200,
    parameter CLKS_PER_BIT = CLK_HZ / BAUD   // 868
)(
    input            clk,
    input            rst,
    input            rx,
    output reg [7:0] rx_data,
    output reg       rx_valid
);
    localparam HALF = CLKS_PER_BIT / 2;

    reg [1:0]  rx_sync;
    wire       rx_s = rx_sync[1];

    always @(posedge clk) rx_sync <= {rx_sync[0], rx};

    localparam S_IDLE  = 2'd0,
               S_START = 2'd1,
               S_DATA  = 2'd2,
               S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    always @(posedge clk) begin
        rx_valid <= 0;
        if (rst) begin
            state   <= S_IDLE;
            cnt     <= 0;
            bit_idx <= 0;
        end else case (state)

        S_IDLE: begin
            if (!rx_s) begin          // falling edge = start bit
                cnt   <= HALF;
                state <= S_START;
            end
        end

        S_START: begin
            if (cnt == 0) begin
                if (!rx_s) begin      // still low → valid start
                    cnt     <= CLKS_PER_BIT - 1;
                    bit_idx <= 0;
                    state   <= S_DATA;
                end else
                    state <= S_IDLE;  // glitch
            end else
                cnt <= cnt - 1;
        end

        S_DATA: begin
            if (cnt == 0) begin
                shift   <= {rx_s, shift[7:1]};
                cnt     <= CLKS_PER_BIT - 1;
                if (bit_idx == 7)
                    state <= S_STOP;
                else
                    bit_idx <= bit_idx + 1;
            end else
                cnt <= cnt - 1;
        end

        S_STOP: begin
            if (cnt == 0) begin
                if (rx_s) begin       // stop bit high → good frame
                    rx_data  <= shift;
                    rx_valid <= 1;
                end
                state <= S_IDLE;
            end else
                cnt <= cnt - 1;
        end

        endcase
    end
endmodule


// ============================================================
//  uart_tx  –  8N1, 100 MHz clock, 115200 baud
//  Assert tx_valid with tx_data; tx_ready goes low while busy.
// ============================================================
module uart_tx #(
    parameter CLK_HZ  = 100_000_000,
    parameter BAUD    = 115_200,
    parameter CLKS_PER_BIT = CLK_HZ / BAUD
)(
    input            clk,
    input            rst,
    input      [7:0] tx_data,
    input            tx_valid,
    output reg       tx_ready,
    output reg       tx
);
    localparam S_IDLE  = 2'd0,
               S_START = 2'd1,
               S_DATA  = 2'd2,
               S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            tx       <= 1'b1;
            tx_ready <= 1'b1;
            cnt      <= 0;
        end else case (state)

        S_IDLE: begin
            tx       <= 1'b1;
            tx_ready <= 1'b1;
            if (tx_valid) begin
                shift    <= tx_data;
                cnt      <= CLKS_PER_BIT - 1;
                tx       <= 1'b0;       // start bit
                tx_ready <= 1'b0;
                bit_idx  <= 0;
                state    <= S_START;
            end
        end

        S_START: begin
            if (cnt == 0) begin
                tx    <= shift[0];
                shift <= {1'b1, shift[7:1]};
                cnt   <= CLKS_PER_BIT - 1;
                state <= S_DATA;
            end else
                cnt <= cnt - 1;
        end

        S_DATA: begin
            if (cnt == 0) begin
                if (bit_idx == 7) begin
                    tx    <= 1'b1;      // stop bit
                    cnt   <= CLKS_PER_BIT - 1;
                    state <= S_STOP;
                end else begin
                    bit_idx <= bit_idx + 1;
                    tx      <= shift[0];
                    shift   <= {1'b1, shift[7:1]};
                    cnt     <= CLKS_PER_BIT - 1;
                end
            end else
                cnt <= cnt - 1;
        end

        S_STOP: begin
            if (cnt == 0)
                state <= S_IDLE;
            else
                cnt <= cnt - 1;
        end

        endcase
    end
endmodule
