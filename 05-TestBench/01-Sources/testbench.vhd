--! \file testbench.vhd
--! \brief Testbench de integracion completo de VICON.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;
use work.sim_utils_pkg.all;
use work.top_pkg.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

entity testbench is
    generic (
        g_MT9V111_RESET_HOLD_US   : integer                      := c_MT9V111_RESET_HOLD_US;
        g_MT9V111_RESET_WAIT_US   : integer                      := c_MT9V111_RESET_WAIT_US;
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

    signal s_clk_base : std_logic;
    signal s_rst_raw  : std_logic;

    signal s_scl_bus : std_logic := 'H';
    signal s_sda_bus : std_logic := 'H';

    signal s_mt_reset_n : std_logic;

    signal s_ftdi_acbus : std_logic_vector(c_FTDI_CONTROLBUS_W-1 downto 0) := (others => 'Z');
    signal s_ftdi_adbus : std_logic_vector(c_FTDI_DATABUS_W-1    downto 0) := (others => 'Z');
    signal s_basys3_sw  : std_logic_vector(c_BASYS3_SW_QTY-1         downto 0) := (others => '0');
    signal s_basys3_led : std_logic_vector(c_BASYS3_LED_QTY-1        downto 0);
    signal s_basys3_btn : std_logic_vector(c_BASYS3_BTN_QTY-1        downto 0) := (others => '0');
    signal s_basys3_cat : std_logic_vector(c_BASYS3_7SEG_BAR_QTY-1   downto 0);
    signal s_basys3_dp  : std_logic;
    signal s_basys3_an  : std_logic_vector(c_BASYS3_7SEG_DIGIT_QTY-1 downto 0);

    alias a_fsm_state  is <<signal u_dut.s_state                       : main_state_t>>;
    alias a_frame_done is <<signal u_dut.u_frame_capture.frame_done_o  : std_logic>>;
    alias a_rd_data    is <<signal u_dut.s_i2c_rd_data                 : std_logic_vector(15 downto 0)>>;
    alias a_cfg_idx    is <<signal u_dut.s_cfg_idx                     : integer range 0 to 12>>;

    ---------------------------------------------------------------------------
    -- Funcion auxiliar: convierte std_logic a string ACK/NACK
    ---------------------------------------------------------------------------
    function ack_str(a : std_logic) return string is
    begin
        if To_X01(a) = '0' then return "ACK";
        else                     return "NACK";
        end if;
    end function;

begin

    s_scl_bus <= 'H';
    s_sda_bus <= 'H';

    u_clk_rst : entity work.clk_reset_gen
        port map (clk_out => s_clk_base, reset_out => s_rst_raw);

    u_dut : entity work.TOP
        generic map (
            g_USE_ILA               => false,
            g_MT9V111_RESET_HOLD_US => g_MT9V111_RESET_HOLD_US,
            g_MT9V111_RESET_WAIT_US => g_MT9V111_RESET_WAIT_US,
            g_MT9V111_H_RES         => g_MT9V111_H_RES,
            g_MT9V111_V_RES         => g_MT9V111_V_RES,
            g_MT9V111_I2C_FREQ_HZ   => g_MT9V111_I2C_FREQ_HZ,
            g_USE_CAM_SIM           => true,
            g_CAM_SIM_HBLANK        => g_CAM_SIM_HBLANK,
            g_CAM_SIM_VBLANK        => g_CAM_SIM_VBLANK,
            g_CAM_SIM_H_RES         => g_CAM_SIM_H_RES,
            g_CAM_SIM_V_RES         => g_CAM_SIM_V_RES,
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

    u_i2c_agent : entity work.mt9v111_i2c
        generic map (g_I2C_ADDR => c_MT9V111_I2C_SENSOR_ADDR)
        port map (scl_i => s_scl_bus, sda_io => s_sda_bus);

    u_ftdi_agent : entity work.ftdi_agent
        generic map (
            g_LOG_FILE           => "ftdi_rx_log.txt",
            g_TX_FIFO_DEPTH      => 512,
            g_TXE_BUSY_THRESHOLD => 480,
            g_TXE_BUSY_CYCLES    => c_TXE_BUSY_CYCLES   -- 0 = siempre listo
            -- g_PC_TO_FPGA_DEPTH omitido -> default 0, RXF# fijo a '1'
            -- g_PC_TO_FPGA_LOOP  omitido -> default false
        )
        port map (
            acbus_io => s_ftdi_acbus,
            adbus_io => s_ftdi_adbus   -- <-- cambio: adbus_i -> adbus_io
        );

    ---------------------------------------------------------------------------
    -- Monitor FSM
    ---------------------------------------------------------------------------
    p_monitor : process
        variable v_prev_state : main_state_t;
    begin
        wait for 0 ns;
        enable_log_msg(ALL_MESSAGES);
        log(ID_SEQUENCER, "=== VICON Testbench arrancado ===", "TB");
        wait until s_rst_raw = '0';
        log(ID_SEQUENCER, "Reset liberado - FSM arranca", "TB");
        v_prev_state := a_fsm_state;
        loop
            wait on a_fsm_state;
            if a_fsm_state /= v_prev_state then
                case a_fsm_state is
                    when ST_CAM_RESET_ASSERT => log(ID_SEQUENCER, "FSM -> ST_CAM_RESET_ASSERT", "TB");
                    when ST_CAM_RESET_WAIT   => log(ID_SEQUENCER, "FSM -> ST_CAM_RESET_WAIT", "TB");
                    when ST_PAGE_SEL_FILL    => log(ID_SEQUENCER, "FSM -> ST_PAGE_SEL_FILL", "TB");
                    when ST_PAGE_SEL_START   => log(ID_SEQUENCER, "FSM -> ST_PAGE_SEL_START", "TB");
                    when ST_PAGE_SEL_WAIT    => log(ID_SEQUENCER, "FSM -> ST_PAGE_SEL_WAIT", "TB");
                    when ST_CHIPID_RD_START  => log(ID_SEQUENCER, "FSM -> ST_CHIPID_RD_START", "TB");
                    when ST_CHIPID_RD_WAIT   => log(ID_SEQUENCER, "FSM -> ST_CHIPID_RD_WAIT", "TB");
                    when ST_CHIPID_RD_DRAIN  => log(ID_SEQUENCER, "FSM -> ST_CHIPID_RD_DRAIN", "TB");
                    when ST_CFG_PAGE_FILL    => log(ID_SEQUENCER, "FSM -> ST_CFG_PAGE_FILL", "TB");
                    when ST_CFG_PAGE_START   => log(ID_SEQUENCER, "FSM -> ST_CFG_PAGE_START", "TB");
                    when ST_CFG_PAGE_WAIT    => log(ID_SEQUENCER, "FSM -> ST_CFG_PAGE_WAIT", "TB");
                    when ST_CFG_WR_FILL      => log(ID_SEQUENCER, "FSM -> ST_CFG_WR_FILL", "TB");
                    when ST_CFG_WR_START     => log(ID_SEQUENCER, "FSM -> ST_CFG_WR_START", "TB");
                    when ST_CFG_WR_WAIT      => log(ID_SEQUENCER, "FSM -> ST_CFG_WR_WAIT", "TB");
                    when ST_CFG_RD_START     => log(ID_SEQUENCER, "FSM -> ST_CFG_RD_START (verify)", "TB");
                    when ST_CFG_RD_WAIT      => log(ID_SEQUENCER, "FSM -> ST_CFG_RD_WAIT", "TB");
                    when ST_CFG_RD_DRAIN     =>
                        log(ID_SEQUENCER,
                            "FSM -> ST_CFG_RD_DRAIN  idx=" & to_string(a_cfg_idx) &
                            "  rd_data=0x" & to_hstring(a_rd_data), "TB");
                    when ST_CFG_NEXT         => log(ID_SEQUENCER, "FSM -> ST_CFG_NEXT", "TB");
                    when ST_FINISH           =>
                        log(ID_SEQUENCER, "FSM -> ST_FINISH *** Configuracion completada ***", "TB");
                        wait until rising_edge(s_clk_base);
                        wait until rising_edge(s_clk_base);
                        check_value(s_basys3_led(0), '1', ERROR,
                                    "LED(0) debe estar encendido en ST_FINISH", "TB");
                    when ST_ERROR =>
                        alert(ERROR,
                            "FSM -> ST_ERROR - verify fallido en idx=" & to_string(a_cfg_idx) &
                            "  rd_data=0x" & to_hstring(a_rd_data));
                    when others =>
                        log(ID_SEQUENCER, "FSM -> estado desconocido", "TB");
                end case;
                v_prev_state := a_fsm_state;
            end if;
        end loop;
    end process p_monitor;

    ---------------------------------------------------------------------------
    -- Monitor de frames
    ---------------------------------------------------------------------------
    p_frame_monitor : process
        variable v_frame_cnt : natural := 0;
    begin
        wait until s_rst_raw = '0';
        loop
            wait until rising_edge(a_frame_done);
            v_frame_cnt := v_frame_cnt + 1;
            log(ID_SEQUENCER, "Frame " & to_string(v_frame_cnt) & " completado", "TB");
        end loop;
    end process p_frame_monitor;

---------------------------------------------------------------------------
    -- Sniffer I2C
    -- Lee bit a bit del bus y decodifica START, STOP, RSTART, bytes y ACK/NACK
    ---------------------------------------------------------------------------
    p_i2c_sniffer : process

        -- Lee un bit. Devuelve el bit muestreado en flanco de subida de SCL.
        -- Si durante la ventana de SCL alto SDA cambia, reporta rstart o stop.
        procedure read_bit (
            variable b      : out std_logic;
            variable rstart : out boolean;
            variable stop   : out boolean
        ) is
            variable v_sda_at_rise : std_logic;
        begin
            b      := '0';
            rstart := false;
            stop   := false;

            -- Esperar flanco de subida de SCL
            wait until To_X01(s_scl_bus) = '1';
            v_sda_at_rise := To_X01(s_sda_bus);
            b := v_sda_at_rise;
            if b = 'X' then b := '0'; end if;

            -- Mientras SCL alto, vigilar cambio de SDA
            loop
                wait on s_scl_bus, s_sda_bus;
                -- SCL bajo: fin normal del bit
                if To_X01(s_scl_bus) = '0' then
                    return;
                end if;
                -- SDA bajo con SCL alto: Repeated START
                if To_X01(s_sda_bus) = '0' and To_X01(v_sda_at_rise) /= '0' then
                    rstart := true;
                    return;
                end if;
                -- SDA alto con SCL alto: STOP
                if To_X01(s_sda_bus) = '1' and To_X01(v_sda_at_rise) /= '1' then
                    stop := true;
                    return;
                end if;
            end loop;
        end procedure;

        -- Lee 8 bits MSB primero + el pulso de ACK/NACK.
        -- Si detecta RSTART o STOP durante la lectura, sale inmediatamente.
        procedure read_byte_ack (
            variable data   : out std_logic_vector(7 downto 0);
            variable ack    : out std_logic;
            variable rstart : out boolean;
            variable stop   : out boolean
        ) is
            variable v_bit  : std_logic;
            variable v_rs   : boolean;
            variable v_st   : boolean;
        begin
            data   := (others => '0');
            ack    := '1';
            rstart := false;
            stop   := false;

            for i in 7 downto 0 loop
                read_bit(v_bit, v_rs, v_st);
                if v_rs then rstart := true; return; end if;
                if v_st then stop   := true; return; end if;
                data(i) := v_bit;
            end loop;

            -- Leer ACK/NACK
            read_bit(ack, v_rs, v_st);
            if v_rs then rstart := true; end if;
            if v_st then stop   := true; end if;
        end procedure;

        variable v_byte   : std_logic_vector(7 downto 0);
        variable v_ack    : std_logic;
        variable v_rstart : boolean;
        variable v_stop   : boolean;
        variable v_sda_p  : std_logic := '1';

    begin
        loop
            -- Esperar START: flanco de bajada de SDA con SCL alto
            wait until To_X01(s_sda_bus) = '0';
            if To_X01(s_scl_bus) /= '1' then next; end if;

            log(ID_SEQUENCER, "I2C >> START", "SNIFFER");

            -- Leer byte de direccion
            read_byte_ack(v_byte, v_ack, v_rstart, v_stop);
            if v_rstart then
                log(ID_SEQUENCER, "I2C >> RSTART (inesperado)", "SNIFFER");
                next;
            end if;
            if v_stop then
                log(ID_SEQUENCER, "I2C >> STOP (inesperado)", "SNIFFER");
                next;
            end if;

            if v_byte(0) = '0' then
                log(ID_SEQUENCER,
                    "I2C >> ADDR 0x" & to_hstring("0" & v_byte(7 downto 1)) &
                    " W  " & ack_str(v_ack), "SNIFFER");
            else
                log(ID_SEQUENCER,
                    "I2C >> ADDR 0x" & to_hstring("0" & v_byte(7 downto 1)) &
                    " R  " & ack_str(v_ack), "SNIFFER");
            end if;

            -- Leer bytes hasta STOP o RSTART
            loop
                read_byte_ack(v_byte, v_ack, v_rstart, v_stop);

                if v_stop then
                    log(ID_SEQUENCER, "I2C >> STOP", "SNIFFER");
                    exit;
                end if;

                if v_rstart then
                    log(ID_SEQUENCER, "I2C >> RSTART", "SNIFFER");
                    -- Leer byte de direccion del Repeated START
                    read_byte_ack(v_byte, v_ack, v_rstart, v_stop);
                    if v_byte(0) = '0' then
                        log(ID_SEQUENCER,
                            "I2C >> ADDR 0x" & to_hstring("0" & v_byte(7 downto 1)) &
                            " W  " & ack_str(v_ack), "SNIFFER");
                    else
                        log(ID_SEQUENCER,
                            "I2C >> ADDR 0x" & to_hstring("0" & v_byte(7 downto 1)) &
                            " R  " & ack_str(v_ack), "SNIFFER");
                    end if;
                    next;  -- continuar leyendo bytes de la nueva direccion
                end if;

                log(ID_SEQUENCER,
                    "I2C >> BYTE 0x" & to_hstring(v_byte) &
                    "  " & ack_str(v_ack), "SNIFFER");

            end loop;

        end loop;
    end process p_i2c_sniffer;

end architecture sim;