# Clock constraint
create_clock -period 10.0 -name clk [get_ports clk]

# Reset (optional - async)
set_false_path -from [get_ports rst_n]

# BRAM timing multicycle path
set_multicycle_path -setup 2 -from [get_cells *bram*] -to [get_cells *mac*]
