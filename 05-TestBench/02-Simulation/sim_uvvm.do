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
set UVVM       "C:/UVVM"

# -----------------------------------------------------------------
# Procedimientos de utilidad
# ----------------
namespace eval :: {
    proc recompile {} {
        restart -force
        uplevel #0 source sim.do
    }

    proc rerun {} {
        restart -force
        run 50 us
    }
}

# -----------------------------------------------------------------------------
# Crear y mapear librería de trabajo
# -----------------------------------------------------------------------------
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# -----------------------------------------------------------------------------
# Mapear librerías UVVM (ya compiladas en C:/UVVM)
# compile_all.do solo necesita ejecutarse una vez; después solo mapeamos
# -----------------------------------------------------------------------------
vmap uvvm_util              "${UVVM}/uvvm_util/sim/uvvm_util"
vmap uvvm_assertions        "${UVVM}/uvvm_assertions/sim/uvvm_assertions"
vmap uvvm_vvc_framework     "${UVVM}/uvvm_vvc_framework/sim/uvvm_vvc_framework"
vmap bitvis_vip_scoreboard  "${UVVM}/bitvis_vip_scoreboard/sim/bitvis_vip_scoreboard"
vmap bitvis_vip_i2c         "${UVVM}/bitvis_vip_i2c/sim/bitvis_vip_i2c"

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
vcom -2008 -work work "${SRC}/top_pkg.vhd"
vcom -2008 -work work "${SRC}/00-I2C_Controller/i2c_controller.vhd"
vcom -2008 -work work "${SRC}/01-Frame_Capture/frame_capture.vhd"
vcom -2008 -work work "${SRC}/02-FTDI_Controller/ftdi_controller.vhd"
vcom -2008 -work work "${TB_SRC}/00-MT9V111/mt9v111_image.vhd"
vcom -2008 -work work "${TB_SRC}/stubs/ila_stub.vhd"
vcom -2008 -work work "${SRC}/TOP.vhd"

# -----------------------------------------------------------------------------
# Compilar fuentes del testbench
# -----------------------------------------------------------------------------
vcom -2008 -work work "${TB_SRC}/sim_utils_pkg.vhd"
vcom -2008 -work work "${TB_SRC}/clock_generator.vhd"
vcom -2008 -work work "${TB_SRC}/00-MT9V111/mt9v111_i2c.vhd"
vcom -2008 -work work "${TB_SRC}/01-FT232H/ftdi_agent.vhd"
vcom -2008 -suppress 1309 -work work "${TB_SRC}/testbench.vhd"

# -----------------------------------------------------------------------------
# Optimizar preservando visibilidad de señales internas
# -----------------------------------------------------------------------------
vopt work.testbench -o testbench_opt \
    +acc \
    -g g_MT9V111_RESET_HOLD_US=1 \
    -g g_MT9V111_RESET_WAIT_US=2 \
    -g g_MT9V111_I2C_FREQ_HZ=4000000 \
    -g g_USE_CAM_SIM=true \
    -g g_CAM_SIM_HBLANK=10 \
    -g g_CAM_SIM_VBLANK=20 \
    -g g_CAM_SIM_H_RES=100 \
    -g g_CAM_SIM_V_RES=5 \
    -g g_MT9V111_FPS=15 \
    -g g_MT9V111_TARGET_FPS=15 \
    -L unisim -L unisims_ver -L secureip \
    -L xpm -L xilinx_vip -L fifo_generator_v13_2_5 \
    -L uvvm_util -L uvvm_vvc_framework -L bitvis_vip_i2c

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
    -L uvvm_util \
    -L uvvm_vvc_framework \
    -L bitvis_vip_i2c \
    work.testbench_opt

# -----------------------------------------------------------------------------
# Cargar wave personalizado si existe (señales añadidas manualmente)
# -----------------------------------------------------------------------------
if {[file exists wave_saved.do]} {
    echo "Cargando las señales en el wave"
    do wave_saved.do
}

# Cargar los colores del estado del FTDI justo aquí:
if {[file exists radix.do]} {
    echo "Aplicando colores al estado del FTDI..."
    do radix.do
}

# -----------------------------------------------------------------------------
# Configurar ventana de waves
# -----------------------------------------------------------------------------
configure wave -timelineunits us
WaveRestoreZoom {0} {100 us}

# -----------------------------------------------------------------------------
# Breakpoints — parar automáticamente
# -----------------------------------------------------------------------------
set frame_cnt 0
when {/testbench/u_dut/u_frame_capture/frame_done_o'event and /testbench/u_dut/u_frame_capture/frame_done_o = '1'} {
    global frame_cnt
    incr frame_cnt
    echo "Frame $frame_cnt completado en $now"
    if {$frame_cnt >= 2} {
        run 100 us
        stop
    }
}
run -all
