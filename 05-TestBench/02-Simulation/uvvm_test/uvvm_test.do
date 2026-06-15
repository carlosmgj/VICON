# =============================================================================
# uvvm_test.do - Compilación y simulación de tb_axi_bram_dual_aspect
# =============================================================================

# -----------------------------------------------------------------------------
# Rutas base
# -----------------------------------------------------------------------------
set ROOT      "../../../"
set SRC       "${ROOT}01-Sources"
set TB_SRC    "${ROOT}05-TestBench"
set IP_GEN    "${ROOT}06-Project/uvvm_test/uvvm_test.gen/sources_1/ip"
set VIVADO    "C:/Xilinx/Vivado/2020.2"
set SIMLIB    "${ROOT}06-Project/vicon_cmgj/vicon_cmgj.cache/compile_simlib/questa"
set ROOT_UVVM "C:/UVVM"

# -----------------------------------------------------------------------------
# Limpiar entorno de simulación previo
# -----------------------------------------------------------------------------
if {[file exists modelsim.ini]} {
    file delete modelsim.ini
}
vmap -c

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# -----------------------------------------------------------------------------
# Mapear librerías de simulación de Xilinx (unisim, simprim, etc.)
# -----------------------------------------------------------------------------
vmap unisim       "${SIMLIB}/unisim"
vmap unisims_ver  "${SIMLIB}/unisims_ver"
vmap unimacro     "${SIMLIB}/unimacro"
vmap unimacro_ver "${SIMLIB}/unimacro_ver"
vmap secureip     "${SIMLIB}/secureip"
vmap xpm          "${SIMLIB}/xpm"

# -----------------------------------------------------------------------------
# Mapear librerías de UVVM (precompiladas con compile_all.do)
# -----------------------------------------------------------------------------
vmap uvvm_util                  "${ROOT_UVVM}/uvvm_util/sim/uvvm_util"
vmap uvvm_vvc_framework         "${ROOT_UVVM}/uvvm_vvc_framework/sim/uvvm_vvc_framework"
vmap bitvis_vip_scoreboard      "${ROOT_UVVM}/bitvis_vip_scoreboard/sim/bitvis_vip_scoreboard"
vmap bitvis_vip_axilite         "${ROOT_UVVM}/bitvis_vip_axilite/sim/bitvis_vip_axilite"
vmap bitvis_vip_clock_generator "${ROOT_UVVM}/bitvis_vip_clock_generator/sim/bitvis_vip_clock_generator"

# -----------------------------------------------------------------------------
# Compilar IPs de Xilinx (Netlists)
# -----------------------------------------------------------------------------
vcom -2008 -work work "${IP_GEN}/axi_bram_ctrl_0/axi_bram_ctrl_0_sim_netlist.vhdl"
vcom -2008 -work work "${IP_GEN}/blk_mem_gen_0/blk_mem_gen_0_sim_netlist.vhdl"



# -----------------------------------------------------------------------------
# Compilar Testbench
# -----------------------------------------------------------------------------
vcom -2008 -work work "${TB_SRC}/02-Simulation/uvvm_test/tb_axi_bram.vhd"

# -----------------------------------------------------------------------------
# Lanzar simulación
# -----------------------------------------------------------------------------
vsim -t 1fs -noglitch -voptargs="+acc" \
    -L unisim -L unisims_ver -L unimacro -L unimacro_ver -L secureip -L xpm \
    -L uvvm_util -L uvvm_vvc_framework -L bitvis_vip_scoreboard \
    -L bitvis_vip_axilite -L bitvis_vip_clock_generator \
    work.tb_axi_bram_dual_aspect

# -----------------------------------------------------------------------------
# Configuración de visualización de logs UVVM
# -----------------------------------------------------------------------------
# do "${ROOT_UVVM}/script/wave_gen.do"

# -----------------------------------------------------------------------------
# Añadir señales al wave
# -----------------------------------------------------------------------------
# add wave -divider "Clock & Reset"
# add wave -hex /tb_axi_bram_dual_aspect/clk
# add wave -hex /tb_axi_bram_dual_aspect/aresetn

# add wave -divider "AXI4-Lite"
# add wave -hex /tb_axi_bram_dual_aspect/axilite_if/*

# add wave -divider "BRAM Port A"
# add wave -hex /tb_axi_bram_dual_aspect/bram_en_a
# add wave -hex /tb_axi_bram_dual_aspect/bram_we_a
# add wave -hex /tb_axi_bram_dual_aspect/bram_addr_a
# add wave -hex /tb_axi_bram_dual_aspect/bram_wdata_a
# add wave -hex /tb_axi_bram_dual_aspect/bram_rdata_a

# add wave -divider "BRAM Port B (bit-level)"
# add wave -hex /tb_axi_bram_dual_aspect/bram_en_b
# add wave -hex /tb_axi_bram_dual_aspect/bram_addr_b
# add wave -hex /tb_axi_bram_dual_aspect/bram_rdata_b

# # -----------------------------------------------------------------------------
# # Ejecutar
# # -----------------------------------------------------------------------------
# run -all

# wave zoom full