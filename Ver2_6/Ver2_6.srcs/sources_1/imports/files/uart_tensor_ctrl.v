`timescale 1ns / 1ps
// ============================================================
//  uart_tensor_ctrl
//
//  Simple byte-packet protocol over UART to drive tensor_top.
//
//  HOST → FPGA PACKETS
//  ─────────────────────────────────────────────────────────
//  CMD_WRITE_A  (0x01)  addr_hi addr_lo  data_hi data_lo
//  CMD_WRITE_B  (0x02)  addr_hi addr_lo  data_hi data_lo
//  CMD_SET_DIM  (0x03)  M  K  N  op
//  CMD_START    (0x04)
//  CMD_READ_C   (0x05)  addr_hi addr_lo
//
//  FPGA → HOST PACKETS
//  ─────────────────────────────────────────────────────────
//  After CMD_START completes:
//      ACK (0xAA)
//  After CMD_READ_C:
//      byte[ACC/8 .. 0]   MSB first  (ACC bytes, padded to ceil)
//
//  All multi-byte fields are BIG-ENDIAN.
//
//  Parameters must match tensor_top parameters exactly.
// ============================================================


module uart_tensor_ctrl #(
    parameter WIDTH   = 16,
    parameter MAX_DIM = 16,
    parameter ACC     = 2*WIDTH + $clog2(MAX_DIM),
    parameter DEPTH   = MAX_DIM * MAX_DIM,
    parameter ADDR_W  = $clog2(DEPTH),
    parameter ACC_BYTES = (ACC + 7) / 8
)(
    input  clk,
    input  rst,

    input  [7:0] rx_data,
    input        rx_valid,
    output [7:0] tx_data,
    output       tx_valid,
    input        tx_ready,

    output reg                    we_a_ext,
    output reg [ADDR_W-1:0]       addr_a_ext,
    output reg signed [WIDTH-1:0] din_a_ext,

    output reg                    we_b_ext,
    output reg [ADDR_W-1:0]       addr_b_ext,
    output reg signed [WIDTH-1:0] din_b_ext,

    output reg [ADDR_W-1:0]       addr_c_ext,
    input  signed [ACC-1:0]       dout_c_ext,

    output reg [$clog2(MAX_DIM+1)-1:0] M_len,
    output reg [$clog2(MAX_DIM+1)-1:0] K_len,
    output reg [$clog2(MAX_DIM+1)-1:0] N_len,
    output reg [2:0]                   op,
    output reg                         start,
    input                              done
);

    localparam CMD_WRITE_A = 8'h01;
    localparam CMD_WRITE_B = 8'h02;
    localparam CMD_SET_DIM = 8'h03;
    localparam CMD_START   = 8'h04;
    localparam CMD_READ_C  = 8'h05;
    localparam ACK_BYTE    = 8'hAA;

    localparam [4:0]
        S_IDLE        = 5'd0,
        S_WR_AH       = 5'd1,
        S_WR_AL       = 5'd2,
        S_WR_DH       = 5'd3,
        S_WR_DL       = 5'd4,
        S_WR_COMMIT   = 5'd5,
        S_DIM_M       = 5'd6,
        S_DIM_K       = 5'd7,
        S_DIM_N       = 5'd8,
        S_DIM_OP      = 5'd9,
        S_START_PULSE = 5'd10,
        S_WAIT_DONE   = 5'd11,

        // ✅ Fixed ACK states
        S_SEND_ACK        = 5'd12,
        S_SEND_ACK_REQ    = 5'd18,
        S_SEND_ACK_WAIT   = 5'd19,

        S_RC_AH       = 5'd13,
        S_RC_AL       = 5'd14,
        S_RC_WAIT1    = 5'd15,
        S_RC_WAIT2    = 5'd16,

        // ✅ Fixed READ states
        S_RC_SEND     = 5'd17,
        S_RC_REQ      = 5'd20,
        S_RC_WAIT     = 5'd21;

    reg [4:0]  state;
    reg [7:0]  cmd_reg;
    reg [7:0]  addr_hi_r;
    reg [15:0] addr_r;
    reg [7:0]  data_hi_r;

    reg [ACC-1:0]        c_hold;
    reg [$clog2(ACC_BYTES+1)-1:0] byte_idx;

    reg [7:0] tx_reg;
    reg       tx_req;

    assign tx_data  = tx_reg;
    assign tx_valid = tx_req;

    wire [7:0] c_byte;
    assign c_byte = c_hold >> ((ACC_BYTES - 1 - byte_idx) * 8);

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            we_a_ext   <= 0;
            we_b_ext   <= 0;
            start      <= 0;
            tx_req     <= 0;
            M_len      <= 0;
            K_len      <= 0;
            N_len      <= 0;
            op         <= 0;
            addr_c_ext <= 0;

            // ✅ Important resets
            tx_reg     <= 8'h00;
            cmd_reg    <= 8'h00;
            addr_hi_r  <= 8'h00;
            addr_r     <= 16'h0000;
            data_hi_r  <= 8'h00;
            c_hold     <= 0;
            byte_idx   <= 0;
        end else begin
            we_a_ext <= 0;
            we_b_ext <= 0;
            start    <= 0;
            tx_req   <= 0;

            case (state)

            S_IDLE: begin
                if (rx_valid) begin
                    cmd_reg <= rx_data;
                    case (rx_data)
                        CMD_WRITE_A,
                        CMD_WRITE_B : state <= S_WR_AH;
                        CMD_SET_DIM : state <= S_DIM_M;
                        CMD_START   : state <= S_START_PULSE;
                        CMD_READ_C  : state <= S_RC_AH;
                    endcase
                end
            end

            S_WR_AH: if (rx_valid) begin addr_hi_r <= rx_data; state <= S_WR_AL; end
            S_WR_AL: if (rx_valid) begin addr_r <= {addr_hi_r, rx_data}; state <= S_WR_DH; end
            S_WR_DH: if (rx_valid) begin data_hi_r <= rx_data; state <= S_WR_DL; end
            S_WR_DL: if (rx_valid) begin
                if (cmd_reg == CMD_WRITE_A) begin
                    addr_a_ext <= addr_r[ADDR_W-1:0];
                    din_a_ext  <= {data_hi_r, rx_data};
                end else begin
                    addr_b_ext <= addr_r[ADDR_W-1:0];
                    din_b_ext  <= {data_hi_r, rx_data};
                end
                state <= S_WR_COMMIT;
            end

            S_WR_COMMIT: begin
                if (cmd_reg == CMD_WRITE_A) we_a_ext <= 1;
                else                        we_b_ext <= 1;
                state <= S_IDLE;
            end

            S_DIM_M:  if (rx_valid) begin M_len <= rx_data; state <= S_DIM_K; end
            S_DIM_K:  if (rx_valid) begin K_len <= rx_data; state <= S_DIM_N; end
            S_DIM_N:  if (rx_valid) begin N_len <= rx_data; state <= S_DIM_OP; end
            S_DIM_OP: if (rx_valid) begin op    <= rx_data[2:0]; state <= S_IDLE; end

            S_START_PULSE: begin
                start <= 1;
                state <= S_WAIT_DONE;
            end

            S_WAIT_DONE: begin
                if (done) state <= S_SEND_ACK;
            end

            // ✅ FIXED ACK
            S_SEND_ACK: begin
                tx_reg <= ACK_BYTE;
                if (tx_ready) begin
                    tx_req <= 1;
                    state  <= S_IDLE;
                end else begin
                    tx_req <= 1;  // HOLD until ready
                end
            end
            
            S_SEND_ACK_REQ: begin
                tx_req <= 1;
                state  <= S_SEND_ACK_WAIT;
            end

            S_SEND_ACK_WAIT: begin
                tx_req <= 1;
                if (!tx_ready)
                    state <= S_IDLE;
            end

            // READ C
            S_RC_AH: if (rx_valid) begin addr_hi_r <= rx_data; state <= S_RC_AL; end
            S_RC_AL: if (rx_valid) begin addr_r <= {addr_hi_r, rx_data}; state <= S_RC_WAIT1; end

            S_RC_WAIT1: begin
                addr_c_ext <= addr_r[ADDR_W-1:0];
                state <= S_RC_WAIT2;
            end

            S_RC_WAIT2: begin
                c_hold   <= dout_c_ext;
                byte_idx <= 0;
                state    <= S_RC_SEND;
            end

            // ✅ FIXED READ TX
            S_RC_SEND: begin
                tx_reg <= c_byte;
                tx_req <= 1;
            
                if (tx_ready) begin
                    if (byte_idx == ACC_BYTES - 1)
                        state <= S_IDLE;
                    else
                        byte_idx <= byte_idx + 1;
                end
            end

            S_RC_REQ: begin
                tx_req <= 1;
                state  <= S_RC_WAIT;
            end

            S_RC_WAIT: begin
                tx_req <= 1;
                if (!tx_ready) begin
                    if (byte_idx == ACC_BYTES - 1)
                        state <= S_IDLE;
                    else begin
                        byte_idx <= byte_idx + 1;
                        state <= S_RC_SEND;
                    end
                end
            end

            endcase
        end
    end
endmodule
