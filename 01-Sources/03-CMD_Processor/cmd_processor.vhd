--! \file cmd_processor.vhd
--! \brief Procesador de comandos PC->FPGA decodificados por ftdi_controller.
--!
--! Recibe el comando ya decodificado (cmd_valid/cmd_type/cmd_data/cmd_page/cmd_addr)
--! en el dominio ftdi_clk, realiza el CDC hacia clk_o, y expone salidas listas
--! para usar en el TOP:
--!
--!   CMD 0x01 (LED)  -> toggle de led_toggle_o (pulso 1 ciclo en clk_o)
--!   CMD 0x02 (BCD)  -> bcd_o = cmd_data (registrado)
--!   CMD 0x03 (I2C)  -> lanza una transaccion de escritura en i2c_master
--!   CMD 0x04 (CAP)  -> cap_en_o = cmd_data(0) (registrado)
--!
--! El acceso al bus I2C solo se activa cuando i2c_grant_i='1' (tipicamente
--! s_state = ST_FINISH en el TOP). Si llega un comando I2C antes, se descarta.
--!
--! CDC: 3 flip-flops para cmd_valid (deteccion de flanco), 2 para el payload.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;

--! \fsm_show_actions
entity cmd_processor is
    generic (
        g_I2C_FIFO_DEPTH : integer := c_MT9V111_I2C_FIFO_DEPTH
    );
    port (
        ---------------------------------------------------------------------------
        -- Dominio ftdi_clk: comando decodificado por ftdi_controller
        ---------------------------------------------------------------------------
        ftdi_clk_i      : in std_logic;
        ftdi_reset_i    : in std_logic;
        cmd_valid_i     : in std_logic;
        cmd_type_i      : in std_logic_vector(7 downto 0);
        cmd_data_i      : in std_logic_vector(15 downto 0);
        cmd_page_i      : in std_logic;
        cmd_addr_i      : in std_logic_vector(7 downto 0);

        ---------------------------------------------------------------------------
        -- Dominio clk_o (s_mclk): salidas para el TOP
        ---------------------------------------------------------------------------
        clk_o   : in std_logic;
        reset_o : in std_logic;

        -- CMD 0x01 (LED): pulso de 1 ciclo cuando llega un toggle
        led_toggle_o : out std_logic;

        -- CMD 0x02 (BCD): valor registrado
        bcd_o : out std_logic_vector(15 downto 0);

        -- CMD 0x04 (CAP): valor registrado (capture enable)
        cap_en_cmd_o : out std_logic;

        -- Interfaz con i2c_master (solo activa cuando i2c_grant_i='1')
        i2c_grant_i    : in  std_logic;
        i2c_busy_i     : in  std_logic;
        i2c_done_i     : in  std_logic;
        i2c_error_i    : in  std_logic;

        i2c_start_o    : out std_logic;
        i2c_rw_o       : out std_logic;
        i2c_num_regs_o : out integer range 1 to g_I2C_FIFO_DEPTH;
        i2c_addr_reg_o : out std_logic_vector(7 downto 0);
        i2c_wr_push_o  : out std_logic;
        i2c_wr_data_o  : out std_logic_vector(15 downto 0);
        i2c_page_o     : out std_logic  --! Page del comando I2C (gestion de Page Map delegada al llamador)
    );
end entity cmd_processor;

architecture rtl of cmd_processor is

    constant c_CMD_LED : std_logic_vector(7 downto 0) := x"01";
    constant c_CMD_BCD : std_logic_vector(7 downto 0) := x"02";
    constant c_CMD_I2C : std_logic_vector(7 downto 0) := x"03";
    constant c_CMD_CAP : std_logic_vector(7 downto 0) := x"04";

    ---------------------------------------------------------------------------
    -- CDC: ftdi_clk -> clk_o
    ---------------------------------------------------------------------------
    signal s_valid_sync0 : std_logic := '0';
    signal s_valid_sync1 : std_logic := '0';
    signal s_valid_sync2 : std_logic := '0';
    signal s_type_sync0  : std_logic_vector(7 downto 0)  := (others => '0');
    signal s_type_sync1  : std_logic_vector(7 downto 0)  := (others => '0');
    signal s_data_sync0  : std_logic_vector(15 downto 0) := (others => '0');
    signal s_data_sync1  : std_logic_vector(15 downto 0) := (others => '0');
    signal s_page_sync0  : std_logic := '0';
    signal s_page_sync1  : std_logic := '0';
    signal s_addr_sync0  : std_logic_vector(7 downto 0) := (others => '0');
    signal s_addr_sync1  : std_logic_vector(7 downto 0) := (others => '0');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of s_valid_sync0 : signal is "TRUE";
    attribute ASYNC_REG of s_valid_sync1 : signal is "TRUE";

    -- Pulso de comando nuevo en dominio clk_o (flanco de subida de sync1)
    signal s_cmd_pulse : std_logic;

    ---------------------------------------------------------------------------
    -- FSM de ejecucion I2C
    ---------------------------------------------------------------------------
    type t_exec_state is (
        ST_EXEC_IDLE,
        ST_EXEC_I2C_FILL,
        ST_EXEC_I2C_START,
        ST_EXEC_I2C_WAIT
    );
    signal s_exec_state : t_exec_state := ST_EXEC_IDLE;

    -- Comando I2C latcheado mientras se ejecuta (puede tardar varios ciclos)
    signal s_i2c_pending : std_logic := '0';
    signal s_i2c_page_r  : std_logic := '0';
    signal s_i2c_addr_r  : std_logic_vector(7 downto 0)  := (others => '0');
    signal s_i2c_data_r  : std_logic_vector(15 downto 0) := (others => '0');

    -- Registros de salida
    signal s_led_toggle_r : std_logic := '0';
    signal s_bcd_r        : std_logic_vector(15 downto 0) := (others => '0');
    signal s_cap_en_r     : std_logic := '0';

begin

    led_toggle_o <= s_led_toggle_r;
    bcd_o        <= s_bcd_r;
    cap_en_cmd_o <= s_cap_en_r;
    i2c_page_o   <= s_i2c_page_r;

    s_cmd_pulse <= s_valid_sync1 and not s_valid_sync2;

    ---------------------------------------------------------------------------
    -- p_cdc: sincronizadores 2FF (3 para cmd_valid -> deteccion de flanco)
    ---------------------------------------------------------------------------
    p_cdc : process(clk_o)
    begin
        if rising_edge(clk_o) then
            if reset_o = '1' then
                s_valid_sync0 <= '0'; s_valid_sync1 <= '0'; s_valid_sync2 <= '0';
                s_type_sync0  <= (others => '0'); s_type_sync1 <= (others => '0');
                s_data_sync0  <= (others => '0'); s_data_sync1 <= (others => '0');
                s_page_sync0  <= '0'; s_page_sync1 <= '0';
                s_addr_sync0  <= (others => '0'); s_addr_sync1 <= (others => '0');
            else
                s_valid_sync0 <= cmd_valid_i;
                s_valid_sync1 <= s_valid_sync0;
                s_valid_sync2 <= s_valid_sync1;
                s_type_sync0  <= cmd_type_i;
                s_type_sync1  <= s_type_sync0;
                s_data_sync0  <= cmd_data_i;
                s_data_sync1  <= s_data_sync0;
                s_page_sync0  <= cmd_page_i;
                s_page_sync1  <= s_page_sync0;
                s_addr_sync0  <= cmd_addr_i;
                s_addr_sync1  <= s_addr_sync0;
            end if;
        end if;
    end process p_cdc;

    ---------------------------------------------------------------------------
    -- p_dispatch: en el flanco de un comando nuevo, actualizar salidas simples
    -- (LED toggle, BCD, CAP) y latchear el comando I2C si corresponde
    ---------------------------------------------------------------------------
    p_dispatch : process(clk_o)
    begin
        if rising_edge(clk_o) then
            if reset_o = '1' then
                s_led_toggle_r <= '0';
                s_bcd_r        <= (others => '0');
                s_cap_en_r     <= '0';
                s_i2c_pending  <= '0';
                s_i2c_page_r   <= '0';
                s_i2c_addr_r   <= (others => '0');
                s_i2c_data_r   <= (others => '0');
            else
                s_led_toggle_r <= '0';  -- pulso de 1 ciclo

                if s_cmd_pulse = '1' then
                    case s_type_sync1 is

                        when c_CMD_LED =>
                            s_led_toggle_r <= '1';

                        when c_CMD_BCD =>
                            s_bcd_r <= s_data_sync1;

                        when c_CMD_CAP =>
                            s_cap_en_r <= s_data_sync1(0);

                        when c_CMD_I2C =>
                            if i2c_grant_i = '1' and s_i2c_pending = '0' then
                                s_i2c_pending <= '1';
                                s_i2c_page_r  <= s_page_sync1;
                                s_i2c_addr_r  <= s_addr_sync1;
                                s_i2c_data_r  <= s_data_sync1;
                            end if;
                            -- Si i2c_grant_i='0' o ya hay uno pendiente, se descarta

                        when others => null;

                    end case;
                end if;

                -- Limpiar el pending cuando la FSM de ejecucion termina
                if s_exec_state = ST_EXEC_I2C_WAIT and
                   (i2c_done_i = '1' or i2c_error_i = '1') then
                    s_i2c_pending <= '0';
                end if;
            end if;
        end if;
    end process p_dispatch;

    ---------------------------------------------------------------------------
    -- p_exec: FSM de escritura I2C (solo CMD 0x03)
    ---------------------------------------------------------------------------
    p_exec : process(clk_o)
    begin
        if rising_edge(clk_o) then
            if reset_o = '1' then
                s_exec_state   <= ST_EXEC_IDLE;
                i2c_start_o    <= '0';
                i2c_rw_o       <= '0';
                i2c_num_regs_o <= 1;
                i2c_addr_reg_o <= (others => '0');
                i2c_wr_push_o  <= '0';
                i2c_wr_data_o  <= (others => '0');
            else
                i2c_start_o   <= '0';
                i2c_wr_push_o <= '0';

                case s_exec_state is

                    when ST_EXEC_IDLE =>
                        if s_i2c_pending = '1' then
                            s_exec_state <= ST_EXEC_I2C_FILL;
                        end if;

                    -- Encolar el dato a escribir
                    when ST_EXEC_I2C_FILL =>
                        i2c_wr_data_o <= s_i2c_data_r;
                        i2c_wr_push_o <= '1';
                        s_exec_state  <= ST_EXEC_I2C_START;

                    -- Lanzar escritura cuando el master este libre
                    when ST_EXEC_I2C_START =>
                        if i2c_busy_i = '0' then
                            i2c_rw_o       <= '0';  -- escritura
                            i2c_addr_reg_o <= s_i2c_addr_r;
                            i2c_num_regs_o <= 1;
                            i2c_start_o    <= '1';
                            s_exec_state   <= ST_EXEC_I2C_WAIT;
                        end if;

                    when ST_EXEC_I2C_WAIT =>
                        if i2c_done_i = '1' or i2c_error_i = '1' then
                            s_exec_state <= ST_EXEC_IDLE;
                        end if;

                    when others =>
                        s_exec_state <= ST_EXEC_IDLE;

                end case;
            end if;
        end if;
    end process p_exec;

end architecture rtl;