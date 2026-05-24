--! \file testbench.vhd
--! \brief Testbench de integración completo de VICON.
--!
--! Instancias:
--!   - u_clk_rst    : clk_reset_gen  — reloj 100 MHz y reset inicial
--!   - u_dut        : TOP            — DUT completo
--!   - u_i2c_agent  : mt9v111_agent  — esclavo I2C del sensor MT9V111
--!   - u_cam        : cam_sim        — generador de imagen sintética
--!   - u_ftdi_agent : ftdi_agent     — agente FTDI: CLKOUT, TXE#, log de bytes
--!
--! Los genéricos del DUT se sobreescriben con valores reducidos de sim_utils_pkg
--! para acelerar la simulación (tiempos de reset, resolución, frecuencia I2C).
--!
--! Flujo esperado:
--!   1. Reset → FSM arranca en ST_CAM_RESET_ASSERT
--!   2. FSM escribe Page Select (reg 0x01 = 0x0004) vía I2C
--!   3. FSM lee Chip ID (reg 0xFF) → mt9v111_agent responde 0x823A
--!   4. FSM llega a ST_FINISH → LED(0)='1', captura activa
--!   5. cam_sim genera frames → frame_capture escribe FIFO
--!   6. ftdi_controller vacía FIFO → ftdi_agent recibe bytes en ftdi_rx_log.txt

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;
use work.sim_utils_pkg.all;

entity testbench is
end entity testbench;

architecture sim of testbench is

    ---------------------------------------------------------------------------
    -- Señales de reloj y reset
    ---------------------------------------------------------------------------
    signal s_clk_base : std_logic;  --! Reloj 100 MHz generado por u_clk_rst
    signal s_rst_raw  : std_logic;  --! Reset inicial generado por u_clk_rst

    ---------------------------------------------------------------------------
    -- Bus I2C — open-drain; pull-up débil ('H') en reposo
    ---------------------------------------------------------------------------
    signal s_scl_bus : std_logic := 'H';  --! SCL compartido entre TOP y u_i2c_agent
    signal s_sda_bus : std_logic := 'H';  --! SDA compartido entre TOP y u_i2c_agent

    ---------------------------------------------------------------------------
    -- Señales del sensor MT9V111 — dominio pixclk
    ---------------------------------------------------------------------------
    signal s_mt_pixclk  : std_logic;                                         --! mt_clk_o del TOP → pixclk_i de u_cam
    signal s_mt_fvalid  : std_logic;                                         --! Frame valid: u_cam → TOP
    signal s_mt_lvalid  : std_logic;                                         --! Line valid:  u_cam → TOP
    signal s_mt_data    : std_logic_vector(c_MT9V111_DATA_BITS-1 downto 0);  --! Datos:       u_cam → TOP
    signal s_mt_reset_n : std_logic;                                         --! RESET# del sensor (monitorizar)

    ---------------------------------------------------------------------------
    -- Bus FTDI
    -- ACBUS es inout compartido entre TOP y u_ftdi_agent.
    -- Cada uno conduce sus bits y suelta ('Z') los demás.
    ---------------------------------------------------------------------------
    signal s_ftdi_acbus : std_logic_vector(c_FTDI_CONTROLBUS_W-1 downto 0) := (others => 'Z');  --! Bus de control FTDI
    signal s_ftdi_adbus : std_logic_vector(c_FTDI_DATABUS_W-1    downto 0);                     --! Bus de datos FTDI

    ---------------------------------------------------------------------------
    -- Señales Basys3 — periféricos no relevantes para este testbench
    ---------------------------------------------------------------------------
    signal s_basys3_sw  : std_logic_vector(c_BASYS3_SW_QTY-1         downto 0) := (others => '0');
    signal s_basys3_led : std_logic_vector(c_BASYS3_LED_QTY-1         downto 0);
    signal s_basys3_btn : std_logic_vector(c_BASYS3_BTN_QTY-1         downto 0) := (others => '0');
    signal s_basys3_cat : std_logic_vector(c_BASYS3_7SEG_BAR_QTY-1   downto 0);
    signal s_basys3_dp  : std_logic;
    signal s_basys3_an  : std_logic_vector(c_BASYS3_7SEG_DIGIT_QTY-1 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Generador de reloj y reset
    ---------------------------------------------------------------------------
    u_clk_rst : entity work.clk_reset_gen
        port map (
            clk_out   => s_clk_base,
            reset_out => s_rst_raw
        );

    ---------------------------------------------------------------------------
    -- DUT: TOP
    -- Solo se sobreescriben los genéricos que afectan al tiempo de simulación;
    -- el resto usan los defaults de config_pkg.
    ---------------------------------------------------------------------------
    u_dut : entity work.TOP
        generic map (
            g_MT9V111_RESET_HOLD_US => c_SIM_RESET_HOLD_US,
            g_MT9V111_RESET_WAIT_US => c_SIM_RESET_WAIT_US,
            g_MT9V111_H_RES         => c_SIM_H_RES,
            g_MT9V111_V_RES         => c_SIM_V_RES,
            g_MT9V111_I2C_FREQ_HZ   => c_SIM_I2C_FREQ_HZ
        )
        port map (
            basys3_clk_i  => s_clk_base,
            basys3_sw_i   => s_basys3_sw,
            basys3_led_o  => s_basys3_led,
            basys3_cat_o  => s_basys3_cat,
            basys3_dp_o   => s_basys3_dp,
            basys3_an_o   => s_basys3_an,
            basys3_btn_i  => s_basys3_btn,
            mt_data_i     => s_mt_data,
            mt_lvalid_i   => s_mt_lvalid,
            mt_pixclk_i   => s_mt_pixclk,
            mt_fvalid_i   => s_mt_fvalid,
            mt_reset_n_o  => s_mt_reset_n,
            mt_clk_o      => s_mt_pixclk,   --! TOP genera MCLK → u_cam lo usa como pixclk
            i2c_sclk_io   => s_scl_bus,
            i2c_sdata_io  => s_sda_bus,
            ftdi_adbus_o  => s_ftdi_adbus,
            ftdi_acbus_io => s_ftdi_acbus
        );

    ---------------------------------------------------------------------------
    -- Agente I2C: esclavo MT9V111
    -- Los puertos de imagen van a open: u_cam es quien genera pixclk/fval/lval/data
    ---------------------------------------------------------------------------
    u_i2c_agent : entity work.mt9v111_i2c
        generic map (
            g_I2C_ADDR => c_MT9V111_I2C_SENSOR_ADDR
        )
        port map (
            scl_i    => s_scl_bus,
            sda_io   => s_sda_bus,
            pixclk_o => open,
            fvalid_o => open,
            lvalid_o => open,
            data_o   => open
        );

    ---------------------------------------------------------------------------
    -- Generador de imagen sintética
    -- pixclk viene del TOP (mt_clk_o); resolución reducida para simulación.
    ---------------------------------------------------------------------------
    u_cam : entity work.mt9v111_image
        generic map (
            g_H_RES  => c_SIM_H_RES,
            g_V_RES  => c_SIM_V_RES,
            g_HBLANK => c_SIM_HBLANK,
            g_VBLANK => c_SIM_VBLANK
        )
        port map (
            pixclk_i => s_mt_pixclk,
            reset_i  => s_rst_raw,
            fvalid_o => s_mt_fvalid,
            lvalid_o => s_mt_lvalid,
            data_o   => s_mt_data
        );

    ---------------------------------------------------------------------------
    -- Agente FTDI: genera CLKOUT, controla TXE# y registra bytes recibidos
    ---------------------------------------------------------------------------
    u_ftdi_agent : entity work.ftdi_agent
        generic map (
            g_LOG_FILE  => "ftdi_rx_log.txt",
            g_TXE_READY => '0'   --! '0' = FT232H siempre listo (sin backpressure)
        )
        port map (
            acbus_io => s_ftdi_acbus,
            adbus_i  => s_ftdi_adbus
        );

end architecture sim;
