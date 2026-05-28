# =============================================================================
# sim.do — Script de simulación QuestaSim para VICON
# Ejecutar desde: VICON/05-TestBench/02-Simulation/
# =============================================================================

# -----------------------------------------------------------------------------
# Rutas base (relativas al directorio donde se ejecuta este script)
# -----------------------------------------------------------------------------
set ROOT       "../../"
set SRC        "${ROOT}01-Sources"
set TB_SRC     "${ROOT}05-TestBench/01-Sources"
set IP_GEN     "${ROOT}06-Project/vicon_cmgj/vicon_cmgj.gen/sources_1/ip"
set VIVADO     "C:/Xilinx/Vivado/2020.2"
set SIMLIB     "${ROOT}06-Project/vicon_cmgj/vicon_cmgj.cache/compile_simlib/questa"

# -----------------------------------------------------------------------------
# Crear y mapear librería de trabajo
# -----------------------------------------------------------------------------
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# -----------------------------------------------------------------------------
# Mapear librerías de simulación de Vivado (necesarias para las IPs)
# -----------------------------------------------------------------------------
vmap unisim              "${SIMLIB}/unisim"
vmap unisims_ver         "${SIMLIB}/unisims_ver"
vmap secureip            "${SIMLIB}/secureip"
vmap xpm                 "${SIMLIB}/xpm"
vmap xilinx_vip          "${SIMLIB}/xilinx_vip"
vmap fifo_generator_v13_2_5 "${SIMLIB}/fifo_generator_v13_2_5"

# -----------------------------------------------------------------------------
# Compilar IPs de Xilinx
# NOTA: clk_wiz_0 usa el netlist VHDL — el .v provoca error en MMCME2_ADV
# -----------------------------------------------------------------------------
vcom -2008 -work work "${IP_GEN}/clk_wiz_0/clk_wiz_0_sim_netlist.vhdl"
vcom -2008 -work work "${IP_GEN}/fifo_generator_0/fifo_generator_0_sim_netlist.vhdl"

# -----------------------------------------------------------------------------
# Compilar fuentes del diseño (orden: dependencias primero)
# -----------------------------------------------------------------------------
vcom -2008 -work work "${SRC}/Constant_Packages/config_pkg.vhd"
vcom -2008 -work work "${SRC}/00-I2C_Controller/i2c_controller.vhd"
vcom -2008 -work work "${SRC}/01-Frame_Capture/frame_capture.vhd"
vcom -2008 -work work "${SRC}/02-FTDI_Controller/ftdi_controller.vhd"
vcom -2008 -work work "${TB_SRC}/00-MT9V111/mt9v111_image.vhd"
vcom -2008 -work work "${SRC}/TOP.vhd"

# -----------------------------------------------------------------------------
# Compilar fuentes del testbench
# -----------------------------------------------------------------------------
vcom -2008 -work work "${TB_SRC}/sim_utils_pkg.vhd"
vcom -2008 -work work "${TB_SRC}/clock_generator.vhd"
vcom -2008 -work work "${TB_SRC}/00-MT9V111/mt9v111_i2c.vhd"
vcom -2008 -work work "${TB_SRC}/01-FT232H/ftdi_agent.vhd"
vcom -2008 -work work "${TB_SRC}/testbench.vhd"

# -----------------------------------------------------------------------------
# Optimizar preservando visibilidad de señales internas
# -access +r+<ruta> preserva señales que el optimizador eliminaría
# -----------------------------------------------------------------------------
vopt work.testbench -o testbench_opt \
    +acc \
    -L unisim -L unisims_ver -L secureip \
    -L xpm -L xilinx_vip -L fifo_generator_v13_2_5

# -----------------------------------------------------------------------------
# Cargar simulación
# -----------------------------------------------------------------------------
vsim -t 1ps -fsmdebug \
    -L unisim \
    -L unisims_ver \
    -L secureip \
    -L xpm \
    -L xilinx_vip \
    -L fifo_generator_v13_2_5 \
    work.testbench_opt

# -----------------------------------------------------------------------------
# Breakpoints — parar automáticamente al llegar a estados clave
# -----------------------------------------------------------------------------
# when {/testbench/u_dut/s_state = "ST_FINISH"} {
#     run 5 us
#     stop
#     echo ">>> OK: ST_FINISH alcanzado en $now — Chip ID correcto"
# }
# when {/testbench/u_dut/s_state = "ST_ERROR"} {
#     run 5 us
#     stop
#     echo ">>> ERROR: ST_ERROR en $now"
# }

# -----------------------------------------------------------------------------
# Procedimientos de utilidad — disponibles en consola tras el do
# -----------------------------------------------------------------------------
proc ::recompile {} {
    quit -sim
    file delete -force _opt
    file delete -force testbench_opt
    do sim.do
}

proc ::rerun {} {
    quit -sim
    file delete -force testbench_opt
    do sim.do
}



# -----------------------------------------------------------------------------
# Cargar wave personalizado si existe (señales añadidas manualmente)
# -----------------------------------------------------------------------------
if {[file exists wave_saved.do]} {
    do wave_saved.do
}

# -----------------------------------------------------------------------------
# Configurar ventana de waves
# -----------------------------------------------------------------------------
configure wave -timelineunits us
WaveRestoreZoom {0} {100 us}

# -----------------------------------------------------------------------------
# Correr simulación
# -----------------------------------------------------------------------------
run 50 us
