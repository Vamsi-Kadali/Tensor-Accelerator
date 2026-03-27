## =====================================
## CLOCK (100 MHz onboard)
## =====================================
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk -waveform {0 5} [get_ports clk]

## =====================================
## RESET (BTNC)
## =====================================
set_property PACKAGE_PIN C12 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

## =====================================
## START (BTNU)
## =====================================
set_property PACKAGE_PIN D12 [get_ports start]
set_property IOSTANDARD LVCMOS33 [get_ports start]

## =====================================
## DONE (LED0)
## =====================================
set_property PACKAGE_PIN H17 [get_ports done]
set_property IOSTANDARD LVCMOS33 [get_ports done]