`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.03.2026 13:11:46
// Design Name: 
// Module Name: uart_tx
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


module uart_tx
  #(parameter CLKS_PER_BIT = 868)
  (
   input       i_Rst_L,
   input       i_Clock,
   input       i_TX_DV,
   input [7:0] i_TX_Byte,
   output reg  o_TX_Active,
   output reg  o_TX_Serial,
   output reg  o_TX_Done
   );
 
  localparam IDLE         = 3'b000;
  localparam TX_START_BIT = 3'b001;
  localparam TX_DATA_BITS = 3'b010;
  localparam TX_STOP_BIT  = 3'b011;
  localparam CLEANUP      = 3'b100;
 
  reg [2:0] r_SM_Main;
  reg [$clog2(CLKS_PER_BIT):0] r_Clock_Count;
  reg [2:0] r_Bit_Index;
  reg [7:0] r_TX_Data;

  always @(posedge i_Clock or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      r_SM_Main   <= IDLE;
      o_TX_Active <= 0;
      o_TX_Serial <= 1;
      o_TX_Done   <= 0;
    end
    else
    begin
      o_TX_Done <= 1'b0;

      case (r_SM_Main)

      IDLE :
        begin
          o_TX_Serial   <= 1'b1;
          r_Clock_Count <= 0;
          r_Bit_Index   <= 0;

          if (i_TX_DV)
          begin
            o_TX_Active <= 1'b1;
            r_TX_Data   <= i_TX_Byte;
            r_SM_Main   <= TX_START_BIT;
          end
          else
            o_TX_Active <= 1'b0;
        end
     
      TX_START_BIT :
        begin
          o_TX_Serial <= 0;
          if (r_Clock_Count < CLKS_PER_BIT-1)
            r_Clock_Count <= r_Clock_Count + 1;
          else
          begin
            r_Clock_Count <= 0;
            r_SM_Main     <= TX_DATA_BITS;
          end
        end
     
      TX_DATA_BITS :
        begin
          o_TX_Serial <= r_TX_Data[r_Bit_Index];

          if (r_Clock_Count < CLKS_PER_BIT-1)
            r_Clock_Count <= r_Clock_Count + 1;
          else
          begin
            r_Clock_Count <= 0;

            if (r_Bit_Index < 7)
              r_Bit_Index <= r_Bit_Index + 1;
            else
            begin
              r_Bit_Index <= 0;
              r_SM_Main   <= TX_STOP_BIT;
            end
          end
        end
     
      TX_STOP_BIT :
        begin
          o_TX_Serial <= 1;

          if (r_Clock_Count < CLKS_PER_BIT-1)
            r_Clock_Count <= r_Clock_Count + 1;
          else
          begin
            o_TX_Done     <= 1'b1;
            r_Clock_Count <= 0;
            o_TX_Active   <= 0;
            r_SM_Main     <= CLEANUP;
          end
        end
     
      CLEANUP :
        r_SM_Main <= IDLE;

      endcase
    end
  end
endmodule

