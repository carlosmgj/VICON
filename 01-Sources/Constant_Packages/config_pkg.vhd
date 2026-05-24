--! \file config_pkg.vhd
--! \brief Paquete de constantes del proyecto

library ieee;
use ieee.std_logic_1164.all;

package config_pkg is

    constant c_SYSTEM_CLK_FREQ_HZ        : integer := 100_000_000;
    constant c_BASYS3_SW_QTY             : integer := 16;
    constant c_BASYS3_BTN_QTY            : integer := 4;
    constant c_BASYS3_BTN_CENTER         : integer := 0;
    constant c_BASYS3_BTN_RIGHT          : integer := 1;
    constant c_BASYS3_BTN_TOP            : integer := 2;
    constant c_BASYS3_BTN_LEFT           : integer := 3;
    constant c_BASYS3_BTN_DOWN           : integer := 4; 
    constant c_BASYS3_LED_QTY            : integer := 16;
    constant c_BASYS3_7SEG_BAR_QTY       : integer := 7;
    constant c_BASYS3_7SEG_DIGIT_QTY     : integer := 4;
 
     
    constant c_MT9V111_I2C_FREQ_HZ       : integer                       := 400_000;
    constant c_MT9V111_I2C_FIFO_DEPTH    : integer                       := 16;
    constant c_MT9V111_I2C_SENSOR_ADDR   : std_logic_vector(6 downto 0)  := "1011100";
    constant c_MT9V111_DATA_BITS         : integer                       := 8;
    constant c_MT9V111_RESET_HOLD_US     : integer                       := 1;         -- tiempo mínimo según datasheet
    constant c_MT9V111_RESET_WAIT_US     : integer                       := 150000;    -- tiempo de estabilización PLL
    constant c_MT9V111_MCLK_DIV          : integer                       := 2;
    constant c_MT9V111_CHIP_ID_EXPECTED  : std_logic_vector(15 downto 0) := x"823A";
    constant c_MT9V111_H_RES             : integer                       := 640;
    constant c_MT9V111_V_RES             : integer                       := 640;

    constant c_FTDI_DATABUS_W            : integer := 8;
    constant c_FTDI_CONTROLBUS_W         : integer := 8;
    -- FT232H ACBUS pin mapping 
    constant c_FTDI_ACBUS_RXF_N          : integer := 0;  
    constant c_FTDI_ACBUS_TXE_N          : integer := 1;  
    constant c_FTDI_ACBUS_RD_N           : integer := 2;  
    constant c_FTDI_ACBUS_WR_N           : integer := 3;     
    constant c_FTDI_ACBUS_SIWU_N         : integer := 4;  
    constant c_FTDI_ACBUS_CLKOUT         : integer := 5;  
    constant c_FTDI_ACBUS_OE_N           : integer := 6;  
    constant c_FTDI_ACBUS_PWRSAV         : integer := 7;  
 
end package config_pkg; 