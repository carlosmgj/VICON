## @file Basys3_GPIO.xdc
# @brief Archivo de restricciones I/O para la Basys3 (MSEEI 2024-2025)
# @section Diagrama Conexiones
#
# <img src="https://digilent.com/reference/_media/basys3-_basic_io_block_diagram.png?w=600&tok=2661a2"  width="300" />
# @warning En la guia indica para el xdc (No estan en orden con el diagrama):
# - BTN[0]=BTNC;
# - BTN[1]=BTNU;
# - BTN[2]=BTNR;
# - BTN[3]=BTND;
# - BTN[4]=BTNL;
#
# @section author_ Author
# Carlos Manuel Gomez Jimenez, DNI: 76037985P

# Clock signal
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk]

# Switches
set_property PACKAGE_PIN V17 [get_ports {SW[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[0]}]
set_property PACKAGE_PIN V16 [get_ports {SW[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[1]}]
set_property PACKAGE_PIN W16 [get_ports {SW[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[2]}]
set_property PACKAGE_PIN W17 [get_ports {SW[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[3]}]
set_property PACKAGE_PIN W15 [get_ports {SW[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[4]}]
set_property PACKAGE_PIN V15 [get_ports {SW[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[5]}]
set_property PACKAGE_PIN W14 [get_ports {SW[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[6]}]
set_property PACKAGE_PIN W13 [get_ports {SW[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[7]}]
set_property PACKAGE_PIN V2 [get_ports {SW[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[8]}]
set_property PACKAGE_PIN T3 [get_ports {SW[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[9]}]
set_property PACKAGE_PIN T2 [get_ports {SW[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[10]}]
set_property PACKAGE_PIN R3 [get_ports {SW[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[11]}]
set_property PACKAGE_PIN W2 [get_ports {SW[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[12]}]
set_property PACKAGE_PIN U1 [get_ports {SW[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[13]}]
set_property PACKAGE_PIN T1 [get_ports {SW[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[14]}]
set_property PACKAGE_PIN R2 [get_ports {SW[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SW[15]}]


# LEDs
set_property PACKAGE_PIN U16 [get_ports {LED[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[0]}]
set_property PACKAGE_PIN E19 [get_ports {LED[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[1]}]
set_property PACKAGE_PIN U19 [get_ports {LED[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[2]}]
set_property PACKAGE_PIN V19 [get_ports {LED[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[3]}]
set_property PACKAGE_PIN W18 [get_ports {LED[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[4]}]
set_property PACKAGE_PIN U15 [get_ports {LED[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[5]}]
set_property PACKAGE_PIN U14 [get_ports {LED[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[6]}]
set_property PACKAGE_PIN V14 [get_ports {LED[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[7]}]
set_property PACKAGE_PIN V13 [get_ports {LED[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[8]}]
set_property PACKAGE_PIN V3 [get_ports {LED[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[9]}]
set_property PACKAGE_PIN W3 [get_ports {LED[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[10]}]
set_property PACKAGE_PIN U3 [get_ports {LED[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[11]}]
set_property PACKAGE_PIN P3 [get_ports {LED[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[12]}]
set_property PACKAGE_PIN N3 [get_ports {LED[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[13]}]
set_property PACKAGE_PIN P1 [get_ports {LED[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[14]}]
set_property PACKAGE_PIN L1 [get_ports {LED[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {LED[15]}]


#7 segment display
set_property PACKAGE_PIN W7 [get_ports {CAT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAT[0]}]
set_property PACKAGE_PIN W6 [get_ports {CAT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAT[1]}]
set_property PACKAGE_PIN U8 [get_ports {CAT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAT[2]}]
set_property PACKAGE_PIN V8 [get_ports {CAT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAT[3]}]
set_property PACKAGE_PIN U5 [get_ports {CAT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAT[4]}]
set_property PACKAGE_PIN V5 [get_ports {CAT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAT[5]}]
set_property PACKAGE_PIN U7 [get_ports {CAT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAT[6]}]

set_property PACKAGE_PIN V7 [get_ports DP]
set_property IOSTANDARD LVCMOS33 [get_ports DP]

set_property PACKAGE_PIN U2 [get_ports {AN[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[0]}]
set_property PACKAGE_PIN U4 [get_ports {AN[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[1]}]
set_property PACKAGE_PIN V4 [get_ports {AN[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[2]}]
set_property PACKAGE_PIN W4 [get_ports {AN[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[3]}]


#Buttons
set_property PACKAGE_PIN U18 [get_ports {BTN[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[0]}]
set_property PACKAGE_PIN T18 [get_ports {BTN[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[1]}]
set_property PACKAGE_PIN W19 [get_ports {BTN[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[2]}]
set_property PACKAGE_PIN T17 [get_ports {BTN[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[3]}]
set_property PACKAGE_PIN U17 [get_ports {BTN[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {BTN[4]}]

###########################################################
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
###########################################################

#MT9V111
set_property PACKAGE_PIN L3 [get_ports {dout[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dout[0]}]
set_property PACKAGE_PIN M3 [get_ports {dout[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dout[1]}]
set_property PACKAGE_PIN M2 [get_ports {dout[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dout[2]}]
set_property PACKAGE_PIN M1 [get_ports {dout[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dout[3]}]
set_property PACKAGE_PIN N2 [get_ports {dout[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dout[4]}]
set_property PACKAGE_PIN N1 [get_ports {dout[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dout[5]}]
set_property PACKAGE_PIN J1 [get_ports {dout[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dout[6]}]
set_property PACKAGE_PIN K2 [get_ports {dout[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dout[7]}]

set_property PACKAGE_PIN J2 [get_ports line_valid]
set_property IOSTANDARD LVCMOS33 [get_ports line_valid]

set_property PACKAGE_PIN H1 [get_ports pixclk]
set_property IOSTANDARD LVCMOS33 [get_ports pixclk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets pixclk_IBUF]
create_clock -period 40.000 -name pixclk [get_ports pixclk]

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

connect_debug_port u_ila_1/probe3 [get_nets [list u_frame_capture/byte_sel]]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]

