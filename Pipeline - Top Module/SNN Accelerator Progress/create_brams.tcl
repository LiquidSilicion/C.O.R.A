################################################################################
# create_brams.tcl
# Run in Vivado Tcl Console:  source create_brams.tcl
#
# FIX vs previous version:
#   All BRAMs now use  Enable_A {Use_ENA_Pin}  and  Enable_B {Use_ENB_Pin}
#   instead of {Always_Enabled}.
#
#   With Always_Enabled, Vivado hides the ena/enb ports entirely — so when
#   snn_bram_top.v connects .enb(...) it cannot find the port and xsim throws:
#     [VRFC 10-3180] cannot find port 'enb' on this module
#   With Use_ENA_Pin / Use_ENB_Pin the pins are exposed and the existing
#   snn_bram_top.v instantiations compile without any changes.
#
# ──────────────────────────────────────────────────────────────────────────────
# BEFORE RUNNING — DELETE OLD IPs IF THEY EXIST:
#   u_bram_weights.xci   (wrong depth, wrong addr width)
#   u_bram_vm.xci        (superseded by bank_1_vm here)
#
# In Vivado:
#   Sources → Design Sources → right-click → Remove File from Project
# Then:  reset_run synth_1
# ──────────────────────────────────────────────────────────────────────────────
#
# IPs created:
#   bank_1_vm    16-bit × 1024   RAMB18E2   LIF membrane potential V_m
#   bank_1_s    128-bit × 512    RAMB36E2×4 Spike history s[t]
#   bank_3_win   16-bit × 2048   RAMB36E2   W_in weights
#   bank_3_wrec  16-bit × 16384  RAMB36E2×8 W_rec weights
#   bank_3_wout  16-bit × 2048   RAMB36E2   W_out weights
################################################################################

set part "xczu7ev-ffvc1156-2-e"

# ──────────────────────────────────────────────────────────────────────────────
# BANK 1a : V_m — Neuron membrane potential
# 16-bit × 1024 words  (128 used, rest zero-padded)
# Simple Dual Port: Port A write (LIF sweep), Port B read (LIF readback)
# KEY FIX: Enable_A and Enable_B set to Use_ENA_Pin / Use_ENB_Pin so that
#          .ena() and .enb() ports are visible in snn_bram_top.v
# ──────────────────────────────────────────────────────────────────────────────
create_ip -name blk_mem_gen -vendor xilinx.com -library ip \
    -version 8.4 -module_name bank_1_vm

set_property -dict [list \
    CONFIG.Component_Name           {bank_1_vm}              \
    CONFIG.Memory_Type              {Simple_Dual_Port_RAM}   \
    CONFIG.Write_Width_A            {16}                     \
    CONFIG.Write_Depth_A            {1024}                   \
    CONFIG.Read_Width_B             {16}                     \
    CONFIG.Enable_A                 {Use_ENA_Pin}            \
    CONFIG.Enable_B                 {Use_ENB_Pin}            \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File           {false}                  \
    CONFIG.Fill_Remaining_Memory_Locations {true}            \
    CONFIG.Remaining_Memory_Locations {0000}                 \
] [get_ips bank_1_vm]

generate_target all [get_ips bank_1_vm]
puts "✓ bank_1_vm created  (16b × 1024, RAMB18E2, ena/enb pins exposed)"

# ──────────────────────────────────────────────────────────────────────────────
# BANK 1b : S[t] — Spike history (128-bit wide)
# 128-bit × 512 words  → Vivado cascades 4 × RAMB36E2 automatically
# Simple Dual Port: Port A write (MAC saves lif_spikes), Port B read (MAC loads s_prev)
# ──────────────────────────────────────────────────────────────────────────────
create_ip -name blk_mem_gen -vendor xilinx.com -library ip \
    -version 8.4 -module_name bank_1_s

set_property -dict [list \
    CONFIG.Component_Name           {bank_1_s}               \
    CONFIG.Memory_Type              {Simple_Dual_Port_RAM}   \
    CONFIG.Write_Width_A            {128}                    \
    CONFIG.Write_Depth_A            {512}                    \
    CONFIG.Read_Width_B             {128}                    \
    CONFIG.Enable_A                 {Use_ENA_Pin}            \
    CONFIG.Enable_B                 {Use_ENB_Pin}            \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File           {false}                  \
    CONFIG.Fill_Remaining_Memory_Locations {true}            \
    CONFIG.Remaining_Memory_Locations {00000000000000000000000000000000} \
] [get_ips bank_1_s]

generate_target all [get_ips bank_1_s]
puts "✓ bank_1_s created   (128b × 512, 4×RAMB36E2, ena/enb pins exposed)"

# ──────────────────────────────────────────────────────────────────────────────
# BANK 3a : W_in — Input weights
# 16-bit × 2048 words  (NI=16 × NH=128 = 2048 exactly)
# Address range: 0x04000–0x047FF → local [10:0]
# ──────────────────────────────────────────────────────────────────────────────
create_ip -name blk_mem_gen -vendor xilinx.com -library ip \
    -version 8.4 -module_name bank_3_win

set_property -dict [list \
    CONFIG.Component_Name           {bank_3_win}             \
    CONFIG.Memory_Type              {Simple_Dual_Port_RAM}   \
    CONFIG.Write_Width_A            {16}                     \
    CONFIG.Write_Depth_A            {2048}                   \
    CONFIG.Read_Width_B             {16}                     \
    CONFIG.Enable_A                 {Use_ENA_Pin}            \
    CONFIG.Enable_B                 {Use_ENB_Pin}            \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File           {false}                  \
    CONFIG.Fill_Remaining_Memory_Locations {true}            \
    CONFIG.Remaining_Memory_Locations {0000}                 \
] [get_ips bank_3_win]

# Uncomment once you have your w_in.coe:
# set_property CONFIG.Load_Init_File  {true}              [get_ips bank_3_win]
# set_property CONFIG.Coe_File        {/path/to/w_in.coe} [get_ips bank_3_win]

generate_target all [get_ips bank_3_win]
puts "✓ bank_3_win created  (16b × 2048, RAMB36E2, ena/enb pins exposed)"

# ──────────────────────────────────────────────────────────────────────────────
# BANK 3b : W_rec — Recurrent weights
# 16-bit × 16384 words  (NH=128 × NH=128 = 16384)
# Vivado cascades 8 × RAMB36E2 automatically
# Address range: 0x04800–0x07FFF → local [13:0]
# ──────────────────────────────────────────────────────────────────────────────
create_ip -name blk_mem_gen -vendor xilinx.com -library ip \
    -version 8.4 -module_name bank_3_wrec

set_property -dict [list \
    CONFIG.Component_Name           {bank_3_wrec}            \
    CONFIG.Memory_Type              {Simple_Dual_Port_RAM}   \
    CONFIG.Write_Width_A            {16}                     \
    CONFIG.Write_Depth_A            {16384}                  \
    CONFIG.Read_Width_B             {16}                     \
    CONFIG.Enable_A                 {Use_ENA_Pin}            \
    CONFIG.Enable_B                 {Use_ENB_Pin}            \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File           {false}                  \
    CONFIG.Fill_Remaining_Memory_Locations {true}            \
    CONFIG.Remaining_Memory_Locations {0000}                 \
] [get_ips bank_3_wrec]

# Uncomment once you have your w_rec.coe:
# set_property CONFIG.Load_Init_File  {true}               [get_ips bank_3_wrec]
# set_property CONFIG.Coe_File        {/path/to/w_rec.coe} [get_ips bank_3_wrec]

generate_target all [get_ips bank_3_wrec]
puts "✓ bank_3_wrec created (16b × 16384, 8×RAMB36E2, ena/enb pins exposed)"

# ──────────────────────────────────────────────────────────────────────────────
# BANK 3c : W_out — Output weights
# 16-bit × 2048 words  (1280 of 2048 used: NH=128 × NO=10)
# Address range: 0x08000–0x084FF → local [10:0]
# 15-bit top-level address required (bit 14 = 1 at 0x08000).
# The old u_bram_weights.xci used [13:0] — that truncated W_out reads into W_rec space.
# ──────────────────────────────────────────────────────────────────────────────
create_ip -name blk_mem_gen -vendor xilinx.com -library ip \
    -version 8.4 -module_name bank_3_wout

set_property -dict [list \
    CONFIG.Component_Name           {bank_3_wout}            \
    CONFIG.Memory_Type              {Simple_Dual_Port_RAM}   \
    CONFIG.Write_Width_A            {16}                     \
    CONFIG.Write_Depth_A            {2048}                   \
    CONFIG.Read_Width_B             {16}                     \
    CONFIG.Enable_A                 {Use_ENA_Pin}            \
    CONFIG.Enable_B                 {Use_ENB_Pin}            \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File           {false}                  \
    CONFIG.Fill_Remaining_Memory_Locations {true}            \
    CONFIG.Remaining_Memory_Locations {0000}                 \
] [get_ips bank_3_wout]

# Uncomment once you have your w_out.coe:
# set_property CONFIG.Load_Init_File  {true}               [get_ips bank_3_wout]
# set_property CONFIG.Coe_File        {/path/to/w_out.coe} [get_ips bank_3_wout]

generate_target all [get_ips bank_3_wout]
puts "✓ bank_3_wout created (16b × 2048, RAMB36E2, ena/enb pins exposed)"

# ──────────────────────────────────────────────────────────────────────────────
puts ""
puts "=== ALL INFERENCE BRAMs CREATED ==="
puts "Physical BRAM usage:"
puts "  1  × RAMB18E2  (bank_1_vm)"
puts "  4  × RAMB36E2  (bank_1_s)"
puts "  1  × RAMB36E2  (bank_3_win)"
puts "  8  × RAMB36E2  (bank_3_wrec)"
puts "  1  × RAMB36E2  (bank_3_wout)"
puts "  ─────────────────────────────"
puts "  1  × RAMB18E2  +  14 × RAMB36E2  total"
puts ""
puts "IMPORTANT: All BRAMs use Use_ENA_Pin / Use_ENB_Pin so that"
puts "  .ena() and .enb() port connections in snn_bram_top.v compile correctly."
puts ""
puts "REMINDER: window_acc_bram is a SEPARATE IP."
puts "Run create_window_acc_bram.tcl to generate it."
puts ""
puts "REMINDER: Delete u_bram_weights.xci and u_bram_vm.xci if they still"
puts "exist in your project — they conflict with the new IPs above."
# ──────────────────────────────────────────────────────────────────────────────
