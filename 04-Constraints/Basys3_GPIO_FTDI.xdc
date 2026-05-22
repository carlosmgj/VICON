## @file Basys3_GPIO_TEST.xdc
# @brief Archivo de restricciones I/O para la Basys3 : monitorizar señales de chip FTDI
# @section Diagrama Conexiones
#
# @section author_ Author
# Carlos Manuel Gomez Jimenez, DNI: 76037985P

# Clock signal
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk]

###########################################################
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
###########################################################

# set_property PACKAGE_PIN K3 [get_ports pwdn]
# set_property IOSTANDARD LVCMOS33 [get_ports pwdn]

set_property PACKAGE_PIN J3 [get_ports cam_reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports cam_reset_n]

set_property PACKAGE_PIN G3 [get_ports sclk]
set_property IOSTANDARD LVCMOS33 [get_ports sclk]
set_property PULLUP true [get_ports sclk]

set_property PACKAGE_PIN G2 [get_ports sdata]
set_property IOSTANDARD LVCMOS33 [get_ports sdata]
set_property PULLUP true [get_ports sdata]

set_property PACKAGE_PIN H2 [get_ports frame_valid]
set_property IOSTANDARD LVCMOS33 [get_ports frame_valid]

set_property PACKAGE_PIN L2 [get_ports cam_mclk]
set_property IOSTANDARD LVCMOS33 [get_ports cam_mclk]


#UM232H-B

#Bus 1 - BROWN   - D0 - PINPMOD: 1
set_property PACKAGE_PIN A14 [get_ports {ADBUS[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ADBUS[0]}]
#Bus 1 - RED     - D1 - PINPMOD: 7
set_property PACKAGE_PIN A15 [get_ports {ADBUS[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ADBUS[1]}]
#Bus 1 - ORANGE  - D2 - PINPMOD: 2
set_property PACKAGE_PIN A16 [get_ports {ADBUS[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ADBUS[2]}]
#Bus 1 - YELLOW  - D3 - PINPMOD: 8
set_property PACKAGE_PIN A17 [get_ports {ADBUS[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ADBUS[3]}]
#Bus 1 - GREEN   - D4 - PINPMOD: 3
set_property PACKAGE_PIN B15 [get_ports {ADBUS[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ADBUS[4]}]
#Bus 1 - BLUE    - D5 - PINPMOD: 9
set_property PACKAGE_PIN C15 [get_ports {ADBUS[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ADBUS[5]}]
#Bus 1 - PURPLE  - D6 - PINPMOD: 4
set_property PACKAGE_PIN B16 [get_ports {ADBUS[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ADBUS[6]}]
#Bus 1 - GREY    - D7 - PINPMOD: 10
set_property PACKAGE_PIN C16 [get_ports {ADBUS[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ADBUS[7]}]

#Bus 2 - RED     - C0 - PINPMOD: 1
set_property PACKAGE_PIN K17 [get_ports {ACBUS[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ACBUS[0]}]
#Bus 2 - ORANGE  - C1 - PINPMOD: 7
set_property PACKAGE_PIN L17 [get_ports {ACBUS[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ACBUS[1]}]
#Bus 2 - YELLOW  - C2 - PINPMOD: 2
set_property PACKAGE_PIN M18 [get_ports {ACBUS[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ACBUS[2]}]
#Bus 2 - GREEN   - C3 - PINPMOD: 8
set_property PACKAGE_PIN M19 [get_ports {ACBUS[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ACBUS[3]}]
#Bus 2 - BLUE    - C4 - PINPMOD: 3
set_property PACKAGE_PIN N17 [get_ports {ACBUS[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ACBUS[4]}]
#Bus 2 - PURPLE  - C5 - PINPMOD: 9
set_property PACKAGE_PIN P17 [get_ports {ACBUS[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ACBUS[5]}]
#Bus 2 - GREY    - C6 - PINPMOD: 4
set_property PACKAGE_PIN P18 [get_ports {ACBUS[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ACBUS[6]}]
#Bus 2 - WHITE   - C7 - PINPMOD: 10
set_property PACKAGE_PIN R18 [get_ports {ACBUS[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ACBUS[7]}]


set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {ACBUS_IBUF[5]}]
create_clock -period 16.667 -name ftdi_clk [get_ports {ACBUS[5]}]


connect_debug_port u_ila_0/probe1 [get_nets [list {counter[0]} {counter[1]} {counter[2]} {counter[3]} {counter[4]} {counter[5]} {counter[6]} {counter[7]}]]





connect_debug_port u_ila_0/probe3 [get_nets [list debug_c0]]
connect_debug_port u_ila_0/probe4 [get_nets [list debug_c1]]
connect_debug_port u_ila_0/probe5 [get_nets [list debug_c2]]
connect_debug_port u_ila_0/probe6 [get_nets [list debug_c3]]
connect_debug_port u_ila_0/probe7 [get_nets [list debug_c4]]
connect_debug_port u_ila_0/probe8 [get_nets [list debug_c5]]
connect_debug_port u_ila_0/probe9 [get_nets [list debug_c6]]
connect_debug_port u_ila_0/probe10 [get_nets [list debug_c7]]




connect_debug_port u_ila_0/probe4 [get_nets [list debug_oe]]


connect_debug_port u_ila_0/probe1 [get_nets [list {debug_d[0]} {debug_d[1]} {debug_d[2]} {debug_d[3]} {debug_d[4]} {debug_d[5]} {debug_d[6]} {debug_d[7]}]]
connect_debug_port u_ila_0/probe2 [get_nets [list {debug_adbus_in[0]} {debug_adbus_in[1]} {debug_adbus_in[2]} {debug_adbus_in[3]} {debug_adbus_in[4]} {debug_adbus_in[5]} {debug_adbus_in[6]} {debug_adbus_in[7]}]]




create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_IBUF_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 8 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {debug_cnt[0]} {debug_cnt[1]} {debug_cnt[2]} {debug_cnt[3]} {debug_cnt[4]} {debug_cnt[5]} {debug_cnt[6]} {debug_cnt[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 8 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {debug_adbus[0]} {debug_adbus[1]} {debug_adbus[2]} {debug_adbus[3]} {debug_adbus[4]} {debug_adbus[5]} {debug_adbus[6]} {debug_adbus[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 2 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {debug_state[0]} {debug_state[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list debug_rxf]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list debug_txe]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list debug_wr]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
