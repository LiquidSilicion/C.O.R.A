# =============================================================================
# create_window_acc_bram.tcl
# Creates the window_acc_bram used INSIDE s10_window_accumulator.
#
# FIX vs previous version:
#   Enable_A and Enable_B changed from {Always_Enabled} to
#   {Use_ENA_Pin} / {Use_ENB_Pin}.
#
#   With Always_Enabled, Vivado hides the ena/enb ports.
#   s10_window_accumulator.v connects .enb(1'b1) to Port B —
#   that caused:
#     [VRFC 10-3180] cannot find port 'enb' on this module
#       ["...s10_window_accumulator.v":63]
#   With Use_ENB_Pin the port is visible and the error goes away.
#
# Spec (unchanged):
#   Port A : Write — accumulator FSM (8-bit write, 11-bit addr)
#   Port B : Read  — spike_readback  (8-bit read,  11-bit addr)
#   Width  : 8 bits
#   Depth  : 2048 words  (2 ping-pong halves × 16 ch × 50 bins = 1600 used,
#                         rest zero-padded to next power-of-2 = 2048)
#   Mode   : True Dual Port  (simultaneous A-write + B-read)
#   Latency: 1 cycle (no output register)
#   Init   : All zeros
# =============================================================================

create_ip -name blk_mem_gen \
          -vendor xilinx.com \
          -library ip \
          -version 8.4 \
          -module_name window_acc_bram

set_property -dict [list \
    CONFIG.Memory_Type          {True_Dual_Port_RAM}    \
    CONFIG.Write_Width_A        {8}                     \
    CONFIG.Write_Depth_A        {2048}                  \
    CONFIG.Read_Width_A         {8}                     \
    CONFIG.Write_Width_B        {8}                     \
    CONFIG.Write_Depth_B        {2048}                  \
    CONFIG.Read_Width_B         {8}                     \
    CONFIG.Operating_Mode_A     {WRITE_FIRST}           \
    CONFIG.Operating_Mode_B     {READ_FIRST}            \
    CONFIG.Enable_A             {Use_ENA_Pin}           \
    CONFIG.Enable_B             {Use_ENB_Pin}           \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Use_RSTA_Pin         {false}                 \
    CONFIG.Use_RSTB_Pin         {false}                 \
    CONFIG.Fill_Remaining_Memory_Locations {true}       \
    CONFIG.Remaining_Memory_Locations {0}               \
] [get_ips window_acc_bram]

generate_target all [get_files window_acc_bram.xci]

puts "✓ window_acc_bram created"
puts "  True Dual Port, 8-bit × 2048 words, 1 × RAMB18E2"
puts "  ena/enb pins are NOW EXPOSED (Use_ENA_Pin / Use_ENB_Pin)"
puts ""
puts "Port mapping in s10_window_accumulator:"
puts "  .clka  -> clk         .clkb  -> clk"
puts "  .ena   -> bram_ena    .enb   -> 1'b1"
puts "  .wea   -> bram_wea    .web   -> 1'b0"
puts "  .addra -> bram_addra  .addrb -> mac_rd_addr"
puts "  .dina  -> bram_dina   .dinb  -> 8'd0"
puts "  .douta -> (unused)    .doutb -> mac_rd_data"
