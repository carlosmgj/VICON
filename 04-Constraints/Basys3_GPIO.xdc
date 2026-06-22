## @file Basys3_GPIO.xdc
# @brief Archivo de restricciones I/O para la Basys3 (MSEEI 2024-2025)
# @section Diagrama Conexiones
#
# <img src="https://digilent.com/reference/_media/basys3-_basic_io_block_diagram.png?w=600&tok=2661a2"  width="300" />
# @warning En la guia indica para el xdc (No estan en orden con el diagrama):
# - basys3_btn_i[0]=BTNC;
# - basys3_btn_i[1]=BTNU;
# - basys3_btn_i[2]=BTNR;
# - basys3_btn_i[3]=BTND;
# - basys3_btn_i[4]=BTNL;
#
# @section author_ Author
# Carlos Manuel Gomez Jimenez, DNI: 76037985P

# Clock signal
set_property PACKAGE_PIN W5 [get_ports basys3_clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports basys3_clk_i]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports basys3_clk_i]

# Switches
set_property PACKAGE_PIN V17 [get_ports {basys3_sw_i[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[0]}]
set_property PACKAGE_PIN V16 [get_ports {basys3_sw_i[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[1]}]
set_property PACKAGE_PIN W16 [get_ports {basys3_sw_i[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[2]}]
set_property PACKAGE_PIN W17 [get_ports {basys3_sw_i[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[3]}]
set_property PACKAGE_PIN W15 [get_ports {basys3_sw_i[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[4]}]
set_property PACKAGE_PIN V15 [get_ports {basys3_sw_i[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[5]}]
set_property PACKAGE_PIN W14 [get_ports {basys3_sw_i[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[6]}]
set_property PACKAGE_PIN W13 [get_ports {basys3_sw_i[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[7]}]
set_property PACKAGE_PIN V2 [get_ports {basys3_sw_i[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[8]}]
set_property PACKAGE_PIN T3 [get_ports {basys3_sw_i[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[9]}]
set_property PACKAGE_PIN T2 [get_ports {basys3_sw_i[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[10]}]
set_property PACKAGE_PIN R3 [get_ports {basys3_sw_i[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[11]}]
set_property PACKAGE_PIN W2 [get_ports {basys3_sw_i[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[12]}]
set_property PACKAGE_PIN U1 [get_ports {basys3_sw_i[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[13]}]
set_property PACKAGE_PIN T1 [get_ports {basys3_sw_i[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[14]}]
set_property PACKAGE_PIN R2 [get_ports {basys3_sw_i[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_sw_i[15]}]


# LEDs
set_property PACKAGE_PIN U16 [get_ports {basys3_led_o[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[0]}]
set_property PACKAGE_PIN E19 [get_ports {basys3_led_o[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[1]}]
set_property PACKAGE_PIN U19 [get_ports {basys3_led_o[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[2]}]
set_property PACKAGE_PIN V19 [get_ports {basys3_led_o[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[3]}]
set_property PACKAGE_PIN W18 [get_ports {basys3_led_o[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[4]}]
set_property PACKAGE_PIN U15 [get_ports {basys3_led_o[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[5]}]
set_property PACKAGE_PIN U14 [get_ports {basys3_led_o[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[6]}]
set_property PACKAGE_PIN V14 [get_ports {basys3_led_o[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[7]}]
set_property PACKAGE_PIN V13 [get_ports {basys3_led_o[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[8]}]
set_property PACKAGE_PIN V3 [get_ports {basys3_led_o[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[9]}]
set_property PACKAGE_PIN W3 [get_ports {basys3_led_o[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[10]}]
set_property PACKAGE_PIN U3 [get_ports {basys3_led_o[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[11]}]
set_property PACKAGE_PIN P3 [get_ports {basys3_led_o[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[12]}]
set_property PACKAGE_PIN N3 [get_ports {basys3_led_o[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[13]}]
set_property PACKAGE_PIN P1 [get_ports {basys3_led_o[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[14]}]
set_property PACKAGE_PIN L1 [get_ports {basys3_led_o[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_led_o[15]}]


#7 segment display
set_property PACKAGE_PIN W7 [get_ports {basys3_cat_o[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_cat_o[0]}]
set_property PACKAGE_PIN W6 [get_ports {basys3_cat_o[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_cat_o[1]}]
set_property PACKAGE_PIN U8 [get_ports {basys3_cat_o[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_cat_o[2]}]
set_property PACKAGE_PIN V8 [get_ports {basys3_cat_o[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_cat_o[3]}]
set_property PACKAGE_PIN U5 [get_ports {basys3_cat_o[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_cat_o[4]}]
set_property PACKAGE_PIN V5 [get_ports {basys3_cat_o[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_cat_o[5]}]
set_property PACKAGE_PIN U7 [get_ports {basys3_cat_o[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_cat_o[6]}]

set_property PACKAGE_PIN V7 [get_ports basys3_dp_o]
set_property IOSTANDARD LVCMOS33 [get_ports basys3_dp_o]

set_property PACKAGE_PIN U2 [get_ports {basys3_an_o[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_an_o[0]}]
set_property PACKAGE_PIN U4 [get_ports {basys3_an_o[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_an_o[1]}]
set_property PACKAGE_PIN V4 [get_ports {basys3_an_o[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_an_o[2]}]
set_property PACKAGE_PIN W4 [get_ports {basys3_an_o[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_an_o[3]}]


#Buttons
set_property PACKAGE_PIN U18 [get_ports {basys3_btn_i[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_btn_i[0]}]
set_property PACKAGE_PIN T18 [get_ports {basys3_btn_i[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_btn_i[1]}]
set_property PACKAGE_PIN W19 [get_ports {basys3_btn_i[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_btn_i[2]}]
set_property PACKAGE_PIN T17 [get_ports {basys3_btn_i[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_btn_i[3]}]
set_property PACKAGE_PIN U17 [get_ports {basys3_btn_i[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {basys3_btn_i[4]}]

###########################################################
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
###########################################################

#MT9V111
set_property PACKAGE_PIN L3 [get_ports {mt_data_i[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {mt_data_i[0]}]
set_property PACKAGE_PIN M3 [get_ports {mt_data_i[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {mt_data_i[1]}]
set_property PACKAGE_PIN M2 [get_ports {mt_data_i[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {mt_data_i[2]}]
set_property PACKAGE_PIN M1 [get_ports {mt_data_i[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {mt_data_i[3]}]
set_property PACKAGE_PIN N2 [get_ports {mt_data_i[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {mt_data_i[4]}]
set_property PACKAGE_PIN N1 [get_ports {mt_data_i[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {mt_data_i[5]}]
set_property PACKAGE_PIN J1 [get_ports {mt_data_i[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {mt_data_i[6]}]
set_property PACKAGE_PIN K2 [get_ports {mt_data_i[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {mt_data_i[7]}]

set_property PACKAGE_PIN J2 [get_ports mt_lvalid_i]
set_property IOSTANDARD LVCMOS33 [get_ports mt_lvalid_i]

set_property PACKAGE_PIN H1 [get_ports mt_pixclk_i]
set_property IOSTANDARD LVCMOS33 [get_ports mt_pixclk_i]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets mt_pixclk_i_IBUF]
create_clock -period 40.000 -name mt_pixclk_i [get_ports mt_pixclk_i]

# set_property PACKAGE_PIN K3 [get_ports pwdn]
# set_property IOSTANDARD LVCMOS33 [get_ports pwdn]

set_property PACKAGE_PIN J3 [get_ports mt_reset_n_o]
set_property IOSTANDARD LVCMOS33 [get_ports mt_reset_n_o]

set_property PACKAGE_PIN G3 [get_ports i2c_sclk_io]
set_property IOSTANDARD LVCMOS33 [get_ports i2c_sclk_io]
set_property PULLUP true [get_ports i2c_sclk_io]

set_property PACKAGE_PIN G2 [get_ports i2c_sdata_io]
set_property IOSTANDARD LVCMOS33 [get_ports i2c_sdata_io]
set_property PULLUP true [get_ports i2c_sdata_io]

set_property PACKAGE_PIN H2 [get_ports mt_fvalid_i]
set_property IOSTANDARD LVCMOS33 [get_ports mt_fvalid_i]

set_property PACKAGE_PIN L2 [get_ports mt_clk_o]
set_property IOSTANDARD LVCMOS33 [get_ports mt_clk_o]


#UM232H-B

#Bus 1 - BROWN   - D0 - PINPMOD: 1
set_property PACKAGE_PIN A14 [get_ports {ftdi_adbus_io[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_io[0]}]
#Bus 1 - RED     - D1 - PINPMOD: 7
set_property PACKAGE_PIN A15 [get_ports {ftdi_adbus_io[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_io[1]}]
#Bus 1 - ORANGE  - D2 - PINPMOD: 2
set_property PACKAGE_PIN A16 [get_ports {ftdi_adbus_io[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_io[2]}]
#Bus 1 - YELLOW  - D3 - PINPMOD: 8
set_property PACKAGE_PIN A17 [get_ports {ftdi_adbus_io[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_io[3]}]
#Bus 1 - GREEN   - D4 - PINPMOD: 3
set_property PACKAGE_PIN B15 [get_ports {ftdi_adbus_io[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_io[4]}]
#Bus 1 - BLUE    - D5 - PINPMOD: 9
set_property PACKAGE_PIN C15 [get_ports {ftdi_adbus_io[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_io[5]}]
#Bus 1 - PURPLE  - D6 - PINPMOD: 4
set_property PACKAGE_PIN B16 [get_ports {ftdi_adbus_io[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_io[6]}]
#Bus 1 - GREY    - D7 - PINPMOD: 10
set_property PACKAGE_PIN C16 [get_ports {ftdi_adbus_io[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_io[7]}]

#Bus 2 - RED     - C0 - PINPMOD: 1
set_property PACKAGE_PIN K17 [get_ports {ftdi_acbus_io[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_acbus_io[0]}]
#Bus 2 - ORANGE  - C1 - PINPMOD: 7
set_property PACKAGE_PIN L17 [get_ports {ftdi_acbus_io[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_acbus_io[1]}]
#Bus 2 - YELLOW  - C2 - PINPMOD: 2
set_property PACKAGE_PIN M18 [get_ports {ftdi_acbus_io[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_acbus_io[2]}]
#Bus 2 - GREEN   - C3 - PINPMOD: 8
set_property PACKAGE_PIN M19 [get_ports {ftdi_acbus_io[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_acbus_io[3]}]
#Bus 2 - BLUE    - C4 - PINPMOD: 3
set_property PACKAGE_PIN N17 [get_ports {ftdi_acbus_io[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_acbus_io[4]}]
#Bus 2 - PURPLE  - C5 - PINPMOD: 9
set_property PACKAGE_PIN P17 [get_ports {ftdi_acbus_io[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_acbus_io[5]}]
#Bus 2 - GREY    - C6 - PINPMOD: 4
set_property PACKAGE_PIN P18 [get_ports {ftdi_acbus_io[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_acbus_io[6]}]
#Bus 2 - WHITE   - C7 - PINPMOD: 10
set_property PACKAGE_PIN R18 [get_ports {ftdi_acbus_io[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_acbus_io[7]}]

#==========================================================================
# FT232H (UM232H-B) - reloj CLKOUT y timing del bus (modo FT245 Sync FIFO)
#==========================================================================
# CLKOUT lo genera el FT232H y entra por ftdi_acbus_io[5] (ACBUS5, pin P17).
# P17 NO es clock-capable -> CLOCK_DEDICATED_ROUTE FALSE (lo enruta por
# fabric hasta un BUFG; anade skew/jitter, aceptable a 60 MHz).
#
# AVISO SI: a 60 MHz por PMOD con cables sueltos el presupuesto de timing
# es muy ajustado. El skew entre CLKOUT y los bits de datos, la longitud
# de los cables y las posibles resistencias serie del PMOD se comen los
# 7.5 ns de setup. Cables cortos y de igual longitud; si falla timing o da
# errores de datos, considera bajar la frecuencia o cablear mejor.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {ftdi_acbus_io_IBUF[5]}]
create_clock -period 16.667 -name ftdi_clk [get_ports {ftdi_acbus_io[5]}]

#--------------------------------------------------------------------------
# Mapeo ACBUS (estandar FT232H 245 Sync FIFO; CONFIRMAR con config_pkg):
#   [0]=RXF#(in)  [1]=TXE#(in)  [2]=RD#(out)  [3]=WR#(out)
#   [4]=SIWU#(out, normalmente fijo) [5]=CLKOUT(in)  [6]=OE#(out)
#--------------------------------------------------------------------------

# SKEW de placa (cable CLKOUT vs cables de datos). En system-synchronous el
# retardo absoluto de pista de CLKOUT y datos se cancela en gran parte; lo que
# queda es el DESAJUSTE entre ellos. Por eso aqui va el skew, no el retardo
# absoluto. VALOR PARA OPCION A: cables CORTOS e IGUALADOS (~0.15 ns). Si tus
# cables son largos o desiguales, SUBELO (y wr_n/rd_n/oe_n se iran a negativo).
set tpcb_skew_max 0.15
set tpcb_skew_min 0.0

# --- ENTRADAS (FT232H -> FPGA) respecto a ftdi_clk ---------------------
# Tabla 4.1: t5 (CLKOUT->read DATA), t4 (CLKOUT->RXF#), t11 (CLKOUT->TXE#).
# El dato se captura en el SIGUIENTE flanco (pipeline 1 ciclo) -> el setup
# sobra; lo critico es el HOLD (ver nota abajo).
# OJO HOLD: con la inserccion de reloj actual el WHS del bus FTDI queda en
# ~+0.025 ns (al limite). Depende de t_co_in_min real y del skew. Si bajas la
# inserccion de reloj (pin CC), el hold se reduce: re-verifica SIEMPRE.
set t_co_in_max 9.0
set t_co_in_min 1.0
set ftdi_in [get_ports {ftdi_adbus_io[*] ftdi_acbus_io[0] ftdi_acbus_io[1]}]
set_input_delay -clock ftdi_clk -max [expr {$t_co_in_max + $tpcb_skew_max}] $ftdi_in
set_input_delay -clock ftdi_clk -min [expr {$t_co_in_min - $tpcb_skew_max}] $ftdi_in

# --- SALIDAS (FPGA -> FT232H) respecto a ftdi_clk ----------------------
# Tabla 4.1: setup t12/t14 = 7.5 ns ; hold t13/t15 ~ 0 ns.
set t_su_ext 7.5
set t_h_ext  0.0
set ftdi_out [get_ports {ftdi_adbus_io[*] ftdi_acbus_io[2] ftdi_acbus_io[3] ftdi_acbus_io[6]}]
set_output_delay -clock ftdi_clk -max [expr {$t_su_ext + $tpcb_skew_max}] $ftdi_out
set_output_delay -clock ftdi_clk -min [expr {-$t_h_ext - $tpcb_skew_max}] $ftdi_out

# SIWU# (acbus[4]) suele ir fijo; si lo conmutas, restringelo como salida:
# set_output_delay -clock ftdi_clk -max [expr {$t_su_ext + $tpcb_skew_max}] [get_ports {ftdi_acbus_io[4]}]

# --- Empaquetar en IOB los registros de SALIDA del bus FTDI ----------------
# IMPORTANTE: NO pongas IOB TRUE sobre puertos de ENTRADA (RXF#/TXE#) ni sobre
# el puerto inout del bus. IOB sobre un puerto exige un flop pegado a ESE
# terminal; las entradas van a logica combinacional (FSM), no a un registro,
# y Vivado da [Place 30-722]. Marca IOB en las CELDAS de los flops de salida.
#
# Patrones por nombre de registro del controlador (ftdi_controller):
#   s_data_r  -> dato TX (adbus_o)      s_adbus_t -> tristate (adbus_t_o)
#   s_wr_n / s_rd_n / s_oe_n -> control
# Si alguno no empaqueta, revisa el nombre exacto en el log de sintesis.
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *s_data_r_reg*}]
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *s_adbus_t_reg*}]
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *s_wr_n_reg*}]
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *s_rd_n_reg*}]
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *s_oe_n_reg*}]
# (Las entradas RXF#/TXE# y el dato de lectura NO se empaquetan: van
#  combinacionales y su timing ya cumple. Si quisieras empaquetarlas habria que
#  registrarlas explicitamente, lo cual no hace falta en la opcion A.)

# --- Slew/drive de salida: reduce el retardo del OBUF(T) (~3.5 -> ~2.5 ns) --
set_property SLEW FAST  [get_ports {ftdi_adbus_io[*] ftdi_acbus_io[2] ftdi_acbus_io[3] ftdi_acbus_io[6]}]
set_property DRIVE 12   [get_ports {ftdi_adbus_io[*] ftdi_acbus_io[2] ftdi_acbus_io[3] ftdi_acbus_io[6]}]

# --- MULTICYCLE del tristate del bus (opcion A) ----------------------------
# El enable del tristate (s_adbus_t) cambia UNA VEZ POR RAFAGA (Hi-Z<->conduce),
# con ciclos muertos (PRE/PRE2 al entrar, RELEASE/RELEASE2 al salir), NO cada
# ciclo. Cronometrarlo a 1 ciclo es pesimista (falso fallo ~-2 ns); el DATO
# (adbus_o), que es lo que el FT232H muestrea cada flanco, si cumple. El par
# setup-2 / hold-1 refleja la realidad sin tapar nada del camino de dato.
# REQUISITO: que esos ciclos muertos existan en toda la secuencia -> confirmalo
# re-lanzando la sim UVVM (el agente marca contension como 'X').
set_multicycle_path 2 -setup -from [get_cells -hier -filter {NAME =~ *s_adbus_t_reg*}] \
                             -to   [get_ports {ftdi_adbus_io[*]}]
set_multicycle_path 1 -hold  -from [get_cells -hier -filter {NAME =~ *s_adbus_t_reg*}] \
                             -to   [get_ports {ftdi_adbus_io[*]}]

# --- LIMITE DE LA PLACA: inserccion de reloj de CLKOUT ---------------------
# CLKOUT en P17 (NO clock-capable) -> ~5.6 ns de inserccion via BUFG. En la
# Basys3 NINGUN pin de Pmod es clock-capable (solo W5, el oscilador), asi que
# esto no se puede bajar sin cambiar de placa o de modo (async). Por eso, tras
# el multicycle y el empaquetado, lo unico que queda al limite son wr_n/rd_n/
# oe_n (~-0.1 ns): es la holgura que se acepta en la opcion A. Validar en HW
# con cables CORTOS e IGUALADOS (CLKOUT y datos misma longitud).

###########################################################
# CDC False Path - ftdi_clk -> s_mclk
###########################################################
# Primera etapa de los sincronizadores 2FF en cmd_processor
# (s_valid_sync0, s_type_sync0, s_data_sync0, s_addr_sync0).
# La metaestabilidad la resuelve la cadena de sincronizacion;
# se excluye del analisis setup/hold normal entre ftdi_clk y s_mclk.
#
# (Sustituye a los 3 set_false_path antiguos que apuntaban a las
#  senales del proceso p_cdc en TOP.vhd, eliminado por ser codigo
#  muerto: esos destinos (s_cmd_*_sync0_reg*) ya no existen en la
#  netlist.)
set_false_path -from [get_clocks ftdi_clk] \
    -to [get_cells -hierarchical -filter {NAME =~ "*u_cmd_processor/s_*_sync0_reg*"}]

###########################################################
# (OPCIONAL) Agrupar relojes asincronos en vez de false_path sueltos.
# Solo si TODOS los cruces entre dominios estan sincronizados (2FF/FIFO).
# Si lo activas, puedes retirar el set_false_path de arriba.
# set_clock_groups -asynchronous \
#   -group [get_clocks sys_clk_pin] \
#   -group [get_clocks ftdi_clk] \
#   -group [get_clocks mt_pixclk_i]
###########################################################
