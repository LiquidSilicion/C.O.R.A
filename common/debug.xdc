# Clock pins
set_property PACKAGE_PIN F23 [get_ports clk_125_p]
set_property PACKAGE_PIN E23  [get_ports clk_125_n]
set_property IOSTANDARD LVDS [get_ports clk_125_p]
set_property IOSTANDARD LVDS [get_ports clk_125_n]
create_clock -period 8.000 [get_ports clk_125_p]

# Reset
set_property PACKAGE_PIN C3 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# LED
set_property PACKAGE_PIN B5 [get_ports led]
set_property IOSTANDARD LVCMOS33 [get_ports led]


