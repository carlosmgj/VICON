# =============================================================
# simular.do - Script de simulacion para Questa
# Proyecto: vicon_cmgj
# Uso: En la consola de Questa escribir -> do simular.do
# =============================================================

# Rutas base (relativas al proyecto de Questa)
set ROOT "../"
set RTL  "${ROOT}src/rtl"
set TB   "${ROOT}tb"
set SIM  "${ROOT}questa"

# -------------------------------------------------------------
# 1. Limpiar y preparar libreria
# -------------------------------------------------------------
quit -sim
vdel -lib work -all
vlib work
vmap work work

# -------------------------------------------------------------
# 2. Compilar en orden
# -------------------------------------------------------------
vcom -work work -2008 "${TB}/sim_utils_pkg.vhd"
vcom -work work -2008 "${SIM}/clk_wiz_0_sim.vhd"
vcom -work work -2008 "${TB}/clock_generator.vhd"
vcom -work work -2008 "${RTL}/i2c_controller.vhd"
vcom -work work -2008 "${RTL}/TOP.vhd"
vcom -work work -2008 "${TB}/mt9v111.vhd"
vcom -work work -2008 "${TB}/testbench.vhd"

# -------------------------------------------------------------
# 3. Simular
# -------------------------------------------------------------
vsim -voptargs="+acc" work.testbench

# -------------------------------------------------------------
# 4. Cargar configuración de Wave
# -------------------------------------------------------------
do wave.do

# -------------------------------------------------------------
# 5. Correr simulacion
# -------------------------------------------------------------
run 160000 ns
