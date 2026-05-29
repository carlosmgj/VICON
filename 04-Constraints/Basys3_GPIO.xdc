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
set_property PACKAGE_PIN A14 [get_ports {ftdi_adbus_o[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_o[0]}]
#Bus 1 - RED     - D1 - PINPMOD: 7
set_property PACKAGE_PIN A15 [get_ports {ftdi_adbus_o[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_o[1]}]
#Bus 1 - ORANGE  - D2 - PINPMOD: 2
set_property PACKAGE_PIN A16 [get_ports {ftdi_adbus_o[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_o[2]}]
#Bus 1 - YELLOW  - D3 - PINPMOD: 8
set_property PACKAGE_PIN A17 [get_ports {ftdi_adbus_o[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_o[3]}]
#Bus 1 - GREEN   - D4 - PINPMOD: 3
set_property PACKAGE_PIN B15 [get_ports {ftdi_adbus_o[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_o[4]}]
#Bus 1 - BLUE    - D5 - PINPMOD: 9
set_property PACKAGE_PIN C15 [get_ports {ftdi_adbus_o[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_o[5]}]
#Bus 1 - PURPLE  - D6 - PINPMOD: 4
set_property PACKAGE_PIN B16 [get_ports {ftdi_adbus_o[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_o[6]}]
#Bus 1 - GREY    - D7 - PINPMOD: 10
set_property PACKAGE_PIN C16 [get_ports {ftdi_adbus_o[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ftdi_adbus_o[7]}]

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

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {ftdi_acbus_io_IBUF[5]}]
create_clock -period 16.667 -name ftdi_clk [get_ports {ftdi_acbus_io[5]}]
