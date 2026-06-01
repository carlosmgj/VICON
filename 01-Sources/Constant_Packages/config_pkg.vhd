--! \file config_pkg.vhd
--! \brief Paquete de configuración global de VICON.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package config_pkg is
    
    ---------------------------------------------------------------------------
    -- DEBUG
    ---------------------------------------------------------------------------
    constant c_USE_ILA               : boolean := true; --! true → ILA activo (síntesis); false → sin ILA (simulación)
    
    ---------------------------------------------------------------------------
    -- Sistema
    ---------------------------------------------------------------------------
    constant c_SYSTEM_CLK_FREQ_HZ    : integer := 100_000_000; --! Frecuencia del reloj de sistema generado por el MMCM (Hz)
    
    ---------------------------------------------------------------------------
    -- Basys 3 — Recursos de la placa de evaluación
    ---------------------------------------------------------------------------
    constant c_BASYS3_SW_QTY         : integer := 16; --! Número de interruptores deslizantes
    constant c_BASYS3_LED_QTY        : integer := 16; --! Número de LEDs
    constant c_BASYS3_7SEG_BAR_QTY   : integer := 7;  --! Segmentos por dígito del display 7 segmentos
    constant c_BASYS3_7SEG_DIGIT_QTY : integer := 4;  --! Número de dígitos del display 7 segmentos
    constant c_BASYS3_BTN_QTY        : integer := 5;  --! Número de pulsadores \warning original era 4, pero hay 5 definidos (0..4)
    constant c_BASYS3_BTN_CENTER     : integer := 0;  --! Índice del pulsador central
    constant c_BASYS3_BTN_RIGHT      : integer := 1;  --! Índice del pulsador derecho
    constant c_BASYS3_BTN_TOP        : integer := 2;  --! Índice del pulsador superior
    constant c_BASYS3_BTN_LEFT       : integer := 3;  --! Índice del pulsador izquierdo
    constant c_BASYS3_BTN_DOWN       : integer := 4;  --! Índice del pulsador inferior

    ---------------------------------------------------------------------------
    -- MT9V111 — Sensor óptico
    ---------------------------------------------------------------------------
    constant c_MT9V111_I2C_FREQ_HZ      : integer                       := 400_000;   --! Frecuencia del bus I2C (Hz); MT9V111 soporta hasta 400 kHz
    constant c_MT9V111_I2C_FIFO_DEPTH   : integer                       := 16;        --! Profundidad de las FIFOs de escritura y lectura I2C
    constant c_MT9V111_I2C_SENSOR_ADDR  : std_logic_vector(6 downto 0)  := "1011100"; --! Dirección I2C de 7 bits del MT9V111 (0x5C)
    constant c_MT9V111_DATA_BITS        : integer                       := 8;         --! Anchura del bus de datos de imagen del sensor
    constant c_MT9V111_MCLK_DIV         : integer                       := 4;         --! Divisor de c_SYSTEM_CLK_FREQ_HZ para generar mt_clk_o = mclk/(div*2)
    constant c_MT9V111_CHIP_ID_EXPECTED : std_logic_vector(15 downto 0) := x"823A";   --! Chip ID fijo del MT9V111 (registro 0xFF, page 0)
    constant c_MT9V111_H_RES            : integer                       := 640;       --! Resolución horizontal del sensor en píxeles
    constant c_MT9V111_V_RES            : integer                       := 480;       --! Resolución vertical del sensor en píxeles 
    constant c_MT9V111_RESET_HOLD_US    : integer                       := 1;         --! Tiempo mínimo de RESET# a nivel bajo (µs)
    constant c_MT9V111_RESET_WAIT_US    : integer                       := 150_000;   --! Tiempo de espera tras liberar RESET# para estabilización del PLL (µs)
    constant c_MT9V111_FPS              : integer                       := 15     ;   --! FPS que genera el sensor por defecto
    constant c_MT9V111_TARGET_FPS       : integer                       := 15     ;   --! FPS que deseamos adquirir, descartando los restantes. No puede ser mayor que c_MT9V111_FPS
    
    -----------------------------------------------------------------------------------------------------
    -- MT9V111 IMAGE — Uso de generación de imagen sintética (cam_sim) en Hardware para pruebas en simulación y en placa
    -------------------------------------------------------------------------------------------------------
    constant c_USE_CAM_SIM    : boolean := true; --! 1: Usar datos de imagen simulada, 0: usar datos de imagen real
    constant c_CAM_SIM_H_RES  : integer := 255;  --! Resolución horizontal de la imagen sintética generada en píxeles
    constant c_CAM_SIM_V_RES  : integer := 200;  --! Resolución vertical de la imagen sintética generada en líneas
    constant c_CAM_SIM_HBLANK : integer := 20;   --! Blanking horizontal de la imagen sintética (ciclos pixclk): similar a P1 real
    constant c_CAM_SIM_VBLANK : integer := 50;   --! Blanking vertical de la imagen sintética (filas): similar a Reg0x06+9 real

    ---------------------------------------------------------------------------
    -- FT232H — Chip FTDI en modo Synchronous FIFO
    ---------------------------------------------------------------------------
    constant c_FTDI_DATABUS_W    : integer := 8; --! Anchura del bus de datos ADBUS (bits)
    constant c_FTDI_CONTROLBUS_W : integer := 8; --! Anchura del bus de control ACBUS (bits)
    constant c_FTDI_ACBUS_RXF_N  : integer := 0; --! RXF#   — RX empty flag  (entrada): '0'=dato disponible para leer
    constant c_FTDI_ACBUS_TXE_N  : integer := 1; --! TXE#   — TX full flag   (entrada): '0'=FT232H listo para recibir
    constant c_FTDI_ACBUS_RD_N   : integer := 2; --! RD#    — read strobe    (salida):  '0'=leer byte de ADBUS
    constant c_FTDI_ACBUS_WR_N   : integer := 3; --! WR#    — write strobe   (salida):  '0'=escribir byte en ADBUS
    constant c_FTDI_ACBUS_SIWU_N : integer := 4; --! SIWU#  — send immediate (salida):  mantenido a '1' (inactivo)
    constant c_FTDI_ACBUS_CLKOUT : integer := 5; --! CLKOUT — reloj 60 MHz   (entrada): entra vía BUFG como s_ftdi_clk
    constant c_FTDI_ACBUS_OE_N   : integer := 6; --! OE#    — output enable  (salida):  mantenido a '1' (solo escritura)
    constant c_FTDI_ACBUS_PWRSAV : integer := 7; --! PWRSAV — power save     (salida):  mantenido a '1' (activo)

    -- Marcador de inicio de frame (protocolo FPGA → Python)
    constant c_FRAME_MARKER_0 : std_logic_vector(7 downto 0) := x"AA"; --! Byte 0 del marcador
    constant c_FRAME_MARKER_1 : std_logic_vector(7 downto 0) := x"55"; --! Byte 1 del marcador
    constant c_FRAME_MARKER_2 : std_logic_vector(7 downto 0) := x"AA"; --! Byte 2 del marcador
    constant c_FRAME_MARKER_3 : std_logic_vector(7 downto 0) := x"55"; --! Byte 3 del marcador

    -- Valores reservados por el protocolo — no pueden aparecer en datos de imagen
    constant c_PROTO_RESERVED_FF : std_logic_vector(7 downto 0) := x"FF"; --! Sustituido por 0xFE
    constant c_PROTO_RESERVED_00 : std_logic_vector(7 downto 0) := x"00"; --! Sustituido por 0x01
    constant c_PROTO_RESERVED_AA : std_logic_vector(7 downto 0) := x"AA"; --! Sustituido por 0xAB
    constant c_PROTO_RESERVED_55 : std_logic_vector(7 downto 0) := x"55"; --! Sustituido por 0x56

    constant c_PROTO_REPLACE_FF : std_logic_vector(7 downto 0) := x"FE"; --! Sustituto de 0xFF en datos de imagen
    constant c_PROTO_REPLACE_00 : std_logic_vector(7 downto 0) := x"01"; --! Sustituto de 0x00 en datos de imagen
    constant c_PROTO_REPLACE_AA : std_logic_vector(7 downto 0) := x"AB"; --! Sustituto de 0xAA en datos de imagen
    constant c_PROTO_REPLACE_55 : std_logic_vector(7 downto 0) := x"56"; --! Sustituto de 0x55 en datos de imagen

end package config_pkg;