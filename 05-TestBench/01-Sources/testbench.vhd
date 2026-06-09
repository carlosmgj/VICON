--! \file testbench.vhd
--! \brief Testbench de integración completo de VICON.
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
    generic (  
        g_MT9V111_RESET_HOLD_US   : integer                      := c_MT9V111_RESET_HOLD_US;
        g_MT9V111_RESET_WAIT_US   : integer                      := c_MT9V111_RESET_WAIT_US;     --! Sensor real de imagen: Tiempo mínimo de RESET# a nivel bajo según datasheet (µs)
        g_MT9V111_H_RES           : integer                      := c_MT9V111_H_RES;
        g_MT9V111_V_RES           : integer                      := c_MT9V111_V_RES;
        g_MT9V111_I2C_FREQ_HZ     : integer                      := c_MT9V111_I2C_FREQ_HZ;
        g_MT9V111_FPS             : integer                      := c_MT9V111_FPS;
        g_MT9V111_TARGET_FPS      : integer                      := c_MT9V111_TARGET_FPS;
        g_MT9V111_I2C_SENSOR_ADDR : std_logic_vector(6 downto 0) := c_MT9V111_I2C_SENSOR_ADDR;

        g_USE_CAM_SIM             : boolean                      := c_USE_CAM_SIM;
        g_CAM_SIM_HBLANK          : integer                      := c_CAM_SIM_HBLANK;
        g_CAM_SIM_VBLANK          : integer                      := c_CAM_SIM_VBLANK;
        g_CAM_SIM_H_RES           : integer                      := c_CAM_SIM_H_RES;
        g_CAM_SIM_V_RES           : integer                      := c_CAM_SIM_V_RES
        );
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
    -- Señales del sensor MT9V111
    ---------------------------------------------------------------------------
    signal s_mt_reset_n : std_logic;  --! RESET# del sensor (monitorizar)

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

    s_scl_bus <= 'H';
    s_sda_bus <= 'H';
    
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
            g_USE_ILA               => false,
            g_MT9V111_RESET_HOLD_US => g_MT9V111_RESET_HOLD_US,
            g_MT9V111_RESET_WAIT_US => g_MT9V111_RESET_WAIT_US,
            g_MT9V111_H_RES         => g_MT9V111_H_RES,
            g_MT9V111_V_RES         => g_MT9V111_V_RES,
            g_MT9V111_I2C_FREQ_HZ   => g_MT9V111_I2C_FREQ_HZ,
            g_USE_CAM_SIM           => true,                 --! Imagen generada internamente en TOP
            g_CAM_SIM_HBLANK        => g_CAM_SIM_HBLANK,     --! Blanking horizontal reducido para simulación
            g_CAM_SIM_VBLANK        => g_CAM_SIM_VBLANK,     --! Blanking vertical reducido para simulación
            g_CAM_SIM_H_RES         => g_CAM_SIM_H_RES,      --! Resolución horizontal del cam_sim en simulación
            g_CAM_SIM_V_RES         => g_CAM_SIM_V_RES,       --! Resolución vertical del cam_sim en simulación
            g_MT9V111_FPS           => g_MT9V111_FPS,
            g_MT9V111_TARGET_FPS    => g_MT9V111_TARGET_FPS
        )
        port map (
            basys3_clk_i  => s_clk_base,
            basys3_sw_i   => s_basys3_sw,
            basys3_led_o  => s_basys3_led,
            basys3_cat_o  => s_basys3_cat,
            basys3_dp_o   => s_basys3_dp,
            basys3_an_o   => s_basys3_an,
            basys3_btn_i  => s_basys3_btn,
            -- Puertos de imagen no usados con g_USE_CAM_SIM=true
            mt_data_i     => (others => '0'),
            mt_lvalid_i   => '0',
            mt_pixclk_i   => '0',
            mt_fvalid_i   => '0',
            mt_reset_n_o  => s_mt_reset_n,
            mt_clk_o      => open,
            i2c_sclk_io   => s_scl_bus,
            i2c_sdata_io  => s_sda_bus,
            ftdi_adbus_io => s_ftdi_adbus,
            ftdi_acbus_io => s_ftdi_acbus
        );

    ---------------------------------------------------------------------------
    -- Agente I2C: esclavo MT9V111
    -- La imagen es generada internamente por el TOP (g_USE_CAM_SIM=true)
    ---------------------------------------------------------------------------
    u_i2c_agent : entity work.mt9v111_i2c
        generic map (
            g_I2C_ADDR => c_MT9V111_I2C_SENSOR_ADDR
        )
        port map (
            scl_i    => s_scl_bus,
            sda_io   => s_sda_bus
        );

    ---------------------------------------------------------------------------
    -- Agente FTDI: genera CLKOUT, controla TXE# y registra bytes recibidos
    ---------------------------------------------------------------------------
    u_ftdi_agent : entity work.ftdi_agent
        generic map (
            g_LOG_FILE  => "ftdi_rx_log.txt",
            g_TXE_READY => '0',   --! '0' = FT232H siempre listo (sin backpressure)
            g_TXE_READY_CYCLES => c_TXE_READY_CYCLES,
            g_TXE_BUSY_CYCLES  => c_TXE_BUSY_CYCLES
        )
        port map (
            acbus_io => s_ftdi_acbus,
            adbus_i  => s_ftdi_adbus
        );

end architecture sim;