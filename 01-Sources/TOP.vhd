--! \file TOP.vhd
--! \brief VICON: Top Level.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

library work;
use work.config_pkg.all;

--! \brief Entidad de Sistema de Visión.
--! \fsm_show_actions
entity TOP is
    generic (
        g_USE_ILA                   : boolean                      := c_USE_ILA;
        g_SYSTEM_CLK_FREQ_HZ        : integer                      := c_SYSTEM_CLK_FREQ_HZ;
        g_MT9V111_MCLK_DIV          : integer                      := c_MT9V111_MCLK_DIV;
        g_MT9V111_I2C_FREQ_HZ       : integer                      := c_MT9V111_I2C_FREQ_HZ;
        g_MT9V111_I2C_FIFO_DEPTH    : integer                      := c_MT9V111_I2C_FIFO_DEPTH;
        g_MT9V111_I2C_SENSOR_ADDR   : std_logic_vector(6 downto 0) := c_MT9V111_I2C_SENSOR_ADDR;
        g_MT9V111_H_RES             : integer                      := c_MT9V111_H_RES;
        g_MT9V111_V_RES             : integer                      := c_MT9V111_V_RES;
        g_MT9V111_RESET_HOLD_US     : integer                      := c_MT9V111_RESET_HOLD_US;
        g_MT9V111_RESET_WAIT_US     : integer                      := c_MT9V111_RESET_WAIT_US;
        g_MT9V111_FPS               : integer                      := c_MT9V111_FPS;
        g_MT9V111_TARGET_FPS        : integer                      := c_MT9V111_TARGET_FPS;
        g_USE_CAM_SIM               : boolean                      := c_USE_CAM_SIM;
        g_CAM_SIM_HBLANK            : integer                      := c_CAM_SIM_HBLANK;
        g_CAM_SIM_VBLANK            : integer                      := c_CAM_SIM_VBLANK;
        g_CAM_SIM_H_RES             : integer                      := c_CAM_SIM_H_RES;
        g_CAM_SIM_V_RES             : integer                      := c_CAM_SIM_V_RES
    );
    port (
        basys3_clk_i   : in    std_logic;
        basys3_sw_i    : in    std_logic_vector(c_BASYS3_SW_QTY-1         downto 0);
        basys3_led_o   : out   std_logic_vector(c_BASYS3_LED_QTY-1        downto 0);
        basys3_cat_o   : out   std_logic_vector(c_BASYS3_7SEG_BAR_QTY-1   downto 0);
        basys3_dp_o    : out   std_logic;
        basys3_an_o    : out   std_logic_vector(c_BASYS3_7SEG_DIGIT_QTY-1 downto 0);
        basys3_btn_i   : in    std_logic_vector(c_BASYS3_BTN_QTY-1        downto 0);
        mt_data_i      : in    std_logic_vector(c_MT9V111_DATA_BITS-1     downto 0);
        mt_lvalid_i    : in    std_logic;
        mt_pixclk_i    : in    std_logic;
        mt_fvalid_i    : in    std_logic;
        mt_reset_n_o   : out   std_logic;
        mt_clk_o       : out   std_logic;
        i2c_sclk_io    : inout std_logic;
        i2c_sdata_io   : inout std_logic;
        ftdi_adbus_io  : inout std_logic_vector(c_FTDI_DATABUS_W-1        downto 0);  --! ADBUS bidireccional: TX imagen / RX comandos
        ftdi_acbus_io  : inout std_logic_vector(c_FTDI_CONTROLBUS_W-1     downto 0)
    );
end entity TOP;

architecture rtl of TOP is

    ---------------------------------------------------------------------------
    -- Constantes de temporización
    ---------------------------------------------------------------------------
    constant c_MT9V111_RESET_HOLD_CYCLES : integer :=
        (g_SYSTEM_CLK_FREQ_HZ / 1_000_000) * g_MT9V111_RESET_HOLD_US;
    constant c_MT9V111_RESET_WAIT_CYCLES : integer :=
        (g_SYSTEM_CLK_FREQ_HZ / 1_000_000) * g_MT9V111_RESET_WAIT_US;
    constant c_CAP_H_RES : integer :=
        g_CAM_SIM_H_RES * boolean'pos(g_USE_CAM_SIM) +
        g_MT9V111_H_RES * boolean'pos(not g_USE_CAM_SIM);
    constant c_CAP_V_RES : integer :=
        g_CAM_SIM_V_RES * boolean'pos(g_USE_CAM_SIM) +
        g_MT9V111_V_RES * boolean'pos(not g_USE_CAM_SIM);

    ---------------------------------------------------------------------------
    -- Tabla de registros a configurar (Tabla 15 datasheet, MCLK=27 MHz → 30 fps)
    -- Formato: (page, addr, value)
    --   page 0 = Core, page 1 = IFP
    ---------------------------------------------------------------------------
    type t_reg_entry is record
        page : std_logic;                      --! '0'=Core, '1'=IFP
        addr : std_logic_vector(7 downto 0);
        data : std_logic_vector(15 downto 0);
    end record;

    type t_reg_table is array (natural range <>) of t_reg_entry;

    constant c_CFG_TABLE : t_reg_table := (
        -- Core page (page 0)
        ('0', x"05", std_logic_vector(to_unsigned(132,   16))),  --! R5  HBLANK
        ('0', x"06", std_logic_vector(to_unsigned(10,    16))),  --! R6  VBLANK
        ('0', x"07", x"0000"),                                   --! R7  output format
        ('0', x"21", std_logic_vector(to_unsigned(58369, 16))),  --! R33 shutter width
        -- IFP page (page 1)
        ('1', x"33", std_logic_vector(to_unsigned(5137,  16))),  --! R51
        ('1', x"39", std_logic_vector(to_unsigned(290,   16))),  --! R57
        ('1', x"3B", std_logic_vector(to_unsigned(1068,  16))),  --! R59
        ('1', x"3E", std_logic_vector(to_unsigned(4095,  16))),  --! R62
        ('1', x"59", std_logic_vector(to_unsigned(504,   16))),  --! R89
        ('1', x"5A", std_logic_vector(to_unsigned(605,   16))),  --! R90
        ('1', x"5C", std_logic_vector(to_unsigned(8222,  16))),  --! R92
        ('1', x"5D", std_logic_vector(to_unsigned(10021, 16))),  --! R93
        ('1', x"64", std_logic_vector(to_unsigned(4477,  16)))   --! R100
    );

    constant c_CFG_TABLE_LEN : integer := c_CFG_TABLE'length;  --! 13 entradas

    ---------------------------------------------------------------------------
    -- Relojes y reset
    ---------------------------------------------------------------------------
    signal s_mclk         : std_logic;
    signal s_locked       : std_logic;
    signal s_rst_final    : std_logic;
    signal s_mclk_div_cnt : integer range 0 to g_MT9V111_MCLK_DIV - 1 := 0;
    signal cam_mclk_r     : std_logic := '0';  --! clk_out2 del MMCM = 27 MHz

    ---------------------------------------------------------------------------
    -- Interfaz FSM <-> controlador I2C
    ---------------------------------------------------------------------------
    signal s_i2c_rw       : std_logic                                   := '0';
    signal s_i2c_start    : std_logic                                   := '0';
    signal s_i2c_num_regs : integer range 1 to g_MT9V111_I2C_FIFO_DEPTH := 1;
    signal s_i2c_addr_reg : std_logic_vector(7 downto 0)                := (others => '0');
    signal s_i2c_wr_push  : std_logic                                   := '0';
    signal s_i2c_wr_data  : std_logic_vector(15 downto 0)               := (others => '0');
    signal s_i2c_wr_full  : std_logic;
    signal s_i2c_wr_empty : std_logic;
    signal s_i2c_rd_pop   : std_logic                                   := '0';
    signal s_i2c_rd_data  : std_logic_vector(15 downto 0);
    signal s_i2c_rd_full  : std_logic;
    signal s_i2c_rd_empty : std_logic;
    signal s_i2c_busy     : std_logic;
    signal s_i2c_done     : std_logic;
    signal s_i2c_error    : std_logic;
    signal s_scl_out      : std_logic;
    signal s_sda_out      : std_logic;
    signal s_sda_oe       : std_logic;
    signal s_sda_in       : std_logic;

    ---------------------------------------------------------------------------
    -- FTDI
    ---------------------------------------------------------------------------
    signal s_ftdi_clk       : std_logic;
    signal s_ftdi_txe_n     : std_logic;
    signal s_ftdi_rxf_n     : std_logic;                    --! RXF# — dato disponible del PC
    signal s_ftdi_wr_n      : std_logic;
    signal s_ftdi_rd_n      : std_logic;                    --! RD#  — strobe de lectura
    signal s_ftdi_oe_n      : std_logic;                    --! OE#  — habilita salida FTDI en ADBUS
    signal s_ftdi_adbus_out : std_logic_vector(7 downto 0); --! ADBUS hacia el FTDI (TX imagen)
    signal s_ftdi_adbus_in  : std_logic_vector(7 downto 0); --! ADBUS desde el FTDI (RX comandos)
    signal s_ftdi_adbus_oe  : std_logic;                    --! '1'=FPGA conduce ADBUS, '0'=tristate
    signal s_ftdi_tx_active : std_logic;

    -- Comandos decodificados — dominio ftdi_clk
    signal s_cmd_valid_ftdi : std_logic;
    signal s_cmd_type_ftdi  : std_logic_vector(7 downto 0);
    signal s_cmd_data_ftdi  : std_logic_vector(15 downto 0);
    signal s_cmd_page_ftdi  : std_logic;
    signal s_cmd_addr_ftdi  : std_logic_vector(7 downto 0);

    ---------------------------------------------------------------------------
    -- CDC: ftdi_clk → s_mclk (sincronizadores 2FF para cmd_valid y payload)
    ---------------------------------------------------------------------------
    signal s_cmd_valid_sync0 : std_logic := '0';
    signal s_cmd_valid_sync1 : std_logic := '0';
    signal s_cmd_type_sync0  : std_logic_vector(7 downto 0)  := (others => '0');
    signal s_cmd_type_sync1  : std_logic_vector(7 downto 0)  := (others => '0');
    signal s_cmd_data_sync0  : std_logic_vector(15 downto 0) := (others => '0');
    signal s_cmd_data_sync1  : std_logic_vector(15 downto 0) := (others => '0');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of s_cmd_valid_sync0 : signal is "TRUE";
    attribute ASYNC_REG of s_cmd_valid_sync1 : signal is "TRUE";

    ---------------------------------------------------------------------------
    -- FIFO de captura (pixclk → ftdi_clk)
    ---------------------------------------------------------------------------
    signal s_cap_fifo_data  : std_logic_vector(7 downto 0);
    signal s_cap_fifo_wr    : std_logic;
    signal s_cap_fifo_full  : std_logic;
    signal s_cap_fifo_empty : std_logic;
    signal s_cap_fifo_dout  : std_logic_vector(7 downto 0);
    signal s_cap_fifo_rd_en : std_logic;
    signal s_cap_frame_done : std_logic;
    signal s_cap_overflow   : std_logic;
    signal s_cap_en         : std_logic;

    ---------------------------------------------------------------------------
    -- FSM principal
    ---------------------------------------------------------------------------
    type main_state_t is (
        ST_CAM_RESET_ASSERT,    --! RESET# bajo durante RESET_HOLD_CYCLES
        ST_CAM_RESET_WAIT,      --! Espera RESET_WAIT_CYCLES para estabilización del PLL
        -- Lectura Chip ID
        ST_PAGE_SEL_FILL,       --! Encola page=0x0004 → IFP (para leer Chip ID en 0xFF)
        ST_PAGE_SEL_START,      --! Lanza escritura I2C reg 0x01
        ST_PAGE_SEL_WAIT,
        ST_CHIPID_RD_START,     --! Lanza lectura I2C reg 0xFF
        ST_CHIPID_RD_WAIT,
        ST_CHIPID_RD_DRAIN,     --! Extrae y verifica Chip ID
        -- Configuración 30 fps mediante subFSM write+verify
        ST_CFG_PAGE_FILL,       --! Encola el valor de page del registro actual
        ST_CFG_PAGE_START,      --! Lanza escritura Page Map (reg 0x01)
        ST_CFG_PAGE_WAIT,
        ST_CFG_WR_FILL,         --! Encola el dato del registro actual
        ST_CFG_WR_START,        --! Lanza escritura del registro
        ST_CFG_WR_WAIT,
        ST_CFG_RD_START,        --! Lanza lectura del mismo registro (verify)
        ST_CFG_RD_WAIT,
        ST_CFG_RD_DRAIN,        --! Compara readback con valor esperado
        ST_CFG_NEXT,            --! Avanza al siguiente registro o va a ST_FINISH
        -- Estados finales
        ST_FINISH,              --! Configuración OK: captura activa
        ST_ERROR                --! Error I2C, Chip ID o verify fallido
    );

    signal s_state      : main_state_t                                   := ST_CAM_RESET_ASSERT;
    signal s_init_cnt   : integer range 0 to c_MT9V111_RESET_WAIT_CYCLES := 0;
    signal s_fill_cnt   : integer range 0 to g_MT9V111_I2C_FIFO_DEPTH    := 0;
    signal cam_reset_r  : std_logic                                      := '0';
    signal s_chip_id    : std_logic_vector(15 downto 0)                  := (others => '0');
    signal s_led15_r    : std_logic                                      := '0';  --! Registro del LED 15 controlado por comando

    --! Índice en c_CFG_TABLE del registro que se está configurando
    signal s_cfg_idx    : integer range 0 to c_CFG_TABLE_LEN - 1        := 0;
    --! Page del último Page Map enviado (evita reenviar si el siguiente es igual)
    signal s_cur_page   : std_logic                                      := '1';  --! Inicializado a IFP (viene de la lectura del Chip ID)

    ---------------------------------------------------------------------------
    -- Imagen multiplexada (sensor real / cam_sim)
    ---------------------------------------------------------------------------
    signal s_mt_fvalid_int : std_logic;
    signal s_mt_lvalid_int : std_logic;
    signal s_mt_data_int   : std_logic_vector(c_MT9V111_DATA_BITS-1 downto 0);
    signal s_mt_pixclk_int : std_logic;

    ---------------------------------------------------------------------------
    -- Debug (capturado en s_mclk para ILA)
    ---------------------------------------------------------------------------
    signal debug_sclk     : std_logic;
    signal debug_sdata    : std_logic;
    signal debug_dout     : std_logic_vector(7 downto 0);
    signal debug_pixclk   : std_logic;
    signal debug_fval     : std_logic;
    signal debug_lval     : std_logic;
    signal debug_txe_n    : std_logic;
    signal debug_wr_n     : std_logic;
    signal debug_overflow : std_logic;
    signal debug_fifo_wr  : std_logic;

begin

    s_rst_final <= not s_locked;

    i2c_sclk_io  <= '0'       when s_scl_out = '0' else 'Z';
    i2c_sdata_io <= s_sda_out when s_sda_oe  = '1' else 'Z';
    s_sda_in     <= i2c_sdata_io;

    mt_reset_n_o <= cam_reset_r;
    mt_clk_o     <= cam_mclk_r;

    s_cap_en <= '1' when s_state = ST_FINISH else '0';

    ---------------------------------------------------------------------------
    -- FTDI — ADBUS tristate: FPGA conduce cuando adbus_oe='1', tristate cuando '0'
    ---------------------------------------------------------------------------
    ftdi_adbus_io   <= s_ftdi_adbus_out when s_ftdi_adbus_oe = '1' else (others => 'Z');
    s_ftdi_adbus_in <= ftdi_adbus_io;

    ---------------------------------------------------------------------------
    -- FTDI — CLKOUT via BUFG
    ---------------------------------------------------------------------------
    ftdi_clk_buf : BUFG
        port map (I => ftdi_acbus_io(c_FTDI_ACBUS_CLKOUT), O => s_ftdi_clk);

    -- Entradas de control del FTDI
    s_ftdi_rxf_n <= ftdi_acbus_io(c_FTDI_ACBUS_RXF_N);
    s_ftdi_txe_n <= ftdi_acbus_io(c_FTDI_ACBUS_TXE_N);

    -- Salidas de control del FTDI
    ftdi_acbus_io(c_FTDI_ACBUS_RXF_N)  <= 'Z';           --! Entrada — no conducir
    ftdi_acbus_io(c_FTDI_ACBUS_TXE_N)  <= 'Z';           --! Entrada — no conducir
    ftdi_acbus_io(c_FTDI_ACBUS_RD_N)   <= s_ftdi_rd_n;   --! Strobe lectura (controlado por ftdi_controller)
    ftdi_acbus_io(c_FTDI_ACBUS_WR_N)   <= s_ftdi_wr_n;   --! Strobe escritura (controlado por ftdi_controller)
    ftdi_acbus_io(c_FTDI_ACBUS_SIWU_N) <= '1';           --! Send immediate — inactivo
    ftdi_acbus_io(c_FTDI_ACBUS_OE_N)   <= s_ftdi_oe_n;   --! Output enable FTDI (controlado por ftdi_controller)
    ftdi_acbus_io(c_FTDI_ACBUS_PWRSAV) <= '1';           --! Power save — inactivo

    ---------------------------------------------------------------------------
    -- CDC: ftdi_clk → s_mclk
    -- Solo sincronizamos cmd_valid, cmd_type y cmd_data (suficiente para el toggle)
    ---------------------------------------------------------------------------
    p_cdc : process(s_mclk)
    begin
        if rising_edge(s_mclk) then
            if s_rst_final = '1' then
                s_cmd_valid_sync0 <= '0'; s_cmd_valid_sync1 <= '0';
                s_cmd_type_sync0  <= (others => '0'); s_cmd_type_sync1  <= (others => '0');
                s_cmd_data_sync0  <= (others => '0'); s_cmd_data_sync1  <= (others => '0');
            else
                s_cmd_valid_sync0 <= s_cmd_valid_ftdi;
                s_cmd_valid_sync1 <= s_cmd_valid_sync0;
                s_cmd_type_sync0  <= s_cmd_type_ftdi;
                s_cmd_type_sync1  <= s_cmd_type_sync0;
                s_cmd_data_sync0  <= s_cmd_data_ftdi;
                s_cmd_data_sync1  <= s_cmd_data_sync0;
            end if;
        end if;
    end process p_cdc;

    basys3_cat_o <= (others => '0');
    basys3_dp_o  <= '0';
    basys3_an_o  <= (others => '1');

    ---------------------------------------------------------------------------
    -- Debug
    ---------------------------------------------------------------------------
    p_debug : process(s_mclk)
    begin
        if rising_edge(s_mclk) then
            debug_sclk     <= s_scl_out;
            debug_sdata    <= s_sda_in;
            debug_dout     <= s_mt_data_int;
            debug_pixclk   <= s_mt_pixclk_int;
            debug_fval     <= s_mt_fvalid_int;
            debug_lval     <= s_mt_lvalid_int;
            debug_txe_n    <= s_ftdi_txe_n;
            debug_wr_n     <= s_ftdi_wr_n;
            debug_overflow <= s_cap_overflow;
            debug_fifo_wr  <= s_cap_fifo_wr;
        end if;
    end process p_debug;

    ---------------------------------------------------------------------------
    --! \brief FSM principal de VICON
    --!
    --! Flujo:
    --!   Reset → Chip ID check → configuración 30 fps (write+verify por registro) → captura
    --!
    --! SubFSM write+verify (estados ST_CFG_*):
    --!   Para cada entrada de c_CFG_TABLE:
    --!     1. Si la page cambia respecto a s_cur_page → escribir Page Map (reg 0x01)
    --!     2. Escribir el registro
    --!     3. Leer el registro (readback)
    --!     4. Comparar readback con valor esperado → error si no coincide
    --!     5. Avanzar índice o ir a ST_FINISH
    ---------------------------------------------------------------------------
    p_fsm : process(s_mclk)
    begin
        if rising_edge(s_mclk) then
            if s_rst_final = '1' then
                s_state         <= ST_CAM_RESET_ASSERT;
                cam_reset_r     <= '0';
                s_init_cnt      <= 0;
                s_i2c_rw        <= '0';
                s_i2c_start     <= '0';
                s_i2c_wr_push   <= '0';
                s_i2c_rd_pop    <= '0';
                s_i2c_num_regs  <= 1;
                s_i2c_addr_reg  <= (others => '0');
                s_i2c_wr_data   <= (others => '0');
                s_fill_cnt      <= 0;
                s_chip_id       <= (others => '0');
                s_cfg_idx       <= 0;
                s_cur_page      <= '1';  -- tras Chip ID quedamos en IFP
                basys3_led_o(0) <= '0';
                basys3_led_o(1) <= '0';
                s_led15_r       <= '0';  --! LED 15 apagado en reset
            else
                s_i2c_start   <= '0';
                s_i2c_wr_push <= '0';
                s_i2c_rd_pop  <= '0';

                case s_state is

                    -- ── Reset del sensor ─────────────────────────────────────
                    when ST_CAM_RESET_ASSERT =>
                        cam_reset_r <= '0';
                        if s_init_cnt = c_MT9V111_RESET_HOLD_CYCLES - 1 then
                            s_init_cnt <= 0;
                            s_state    <= ST_CAM_RESET_WAIT;
                        else
                            s_init_cnt <= s_init_cnt + 1;
                        end if;

                    when ST_CAM_RESET_WAIT =>
                        cam_reset_r <= '1';
                        if s_init_cnt = c_MT9V111_RESET_WAIT_CYCLES - 1 then
                            s_init_cnt <= 0;
                            s_state    <= ST_PAGE_SEL_FILL;
                        else
                            s_init_cnt <= s_init_cnt + 1;
                        end if;

                    -- ── Seleccionar IFP page para leer Chip ID ────────────────
                    when ST_PAGE_SEL_FILL =>
                        if s_i2c_wr_full = '0' then
                            s_i2c_wr_data <= x"0004";
                            s_i2c_wr_push <= '1';
                            s_state       <= ST_PAGE_SEL_START;
                        end if;

                    when ST_PAGE_SEL_START =>
                        if s_i2c_busy = '0' then
                            s_i2c_rw       <= '0';
                            s_i2c_addr_reg <= x"01";
                            s_i2c_num_regs <= 1;
                            s_i2c_start    <= '1';
                            s_state        <= ST_PAGE_SEL_WAIT;
                        end if;

                    when ST_PAGE_SEL_WAIT =>
                        if s_i2c_error = '1' then
                            s_state <= ST_ERROR;
                        elsif s_i2c_done = '1' then
                            s_state <= ST_CHIPID_RD_START;
                        end if;

                    -- ── Lectura Chip ID ───────────────────────────────────────
                    when ST_CHIPID_RD_START =>
                        if s_i2c_busy = '0' and s_i2c_rd_empty = '1' then
                            s_i2c_rw       <= '1';
                            s_i2c_addr_reg <= x"FF";
                            s_i2c_num_regs <= 1;
                            s_i2c_start    <= '1';
                            s_state        <= ST_CHIPID_RD_WAIT;
                        end if;

                    when ST_CHIPID_RD_WAIT =>
                        if s_i2c_error = '1' then
                            s_state <= ST_ERROR;
                        elsif s_i2c_done = '1' then
                            s_state <= ST_CHIPID_RD_DRAIN;
                        end if;

                    when ST_CHIPID_RD_DRAIN =>
                        if s_i2c_rd_empty = '0' then
                            s_i2c_rd_pop <= '1';
                            s_chip_id    <= s_i2c_rd_data;
                            if s_i2c_rd_data = c_MT9V111_CHIP_ID_EXPECTED then
                                s_cfg_idx  <= 0;
                                s_cur_page <= '1';  -- Chip ID estaba en IFP
                                s_state    <= ST_CFG_PAGE_FILL;
                            else
                                s_state <= ST_ERROR;
                            end if;
                        end if;

                    -- ════════════════════════════════════════════════════════
                    -- SubFSM write+verify — itera sobre c_CFG_TABLE
                    -- ════════════════════════════════════════════════════════

                    -- ── 1. Cambiar page si es necesario ───────────────────────
                    when ST_CFG_PAGE_FILL =>
                        -- Si la page del registro actual coincide con la actual, saltar
                        if c_CFG_TABLE(s_cfg_idx).page = s_cur_page then
                            s_state <= ST_CFG_WR_FILL;
                        elsif s_i2c_wr_full = '0' then
                            -- Encolar valor de page: '0'→0x0000, '1'→0x0001
                            if c_CFG_TABLE(s_cfg_idx).page = '0' then
                                s_i2c_wr_data <= x"0000";
                            else
                                s_i2c_wr_data <= x"0001";
                            end if;
                            s_i2c_wr_push <= '1';
                            s_state       <= ST_CFG_PAGE_START;
                        end if;

                    when ST_CFG_PAGE_START =>
                        if s_i2c_busy = '0' and s_i2c_rd_empty = '1' then
                            s_i2c_rw       <= '0';
                            s_i2c_addr_reg <= x"01";  --! Page Map register
                            s_i2c_num_regs <= 1;
                            s_i2c_start    <= '1';
                            s_state        <= ST_CFG_PAGE_WAIT;
                        end if;

                    when ST_CFG_PAGE_WAIT =>
                        if s_i2c_error = '1' then
                            s_state <= ST_ERROR;
                        elsif s_i2c_done = '1' then
                            s_cur_page <= c_CFG_TABLE(s_cfg_idx).page;
                            s_state    <= ST_CFG_WR_FILL;
                        end if;

                    -- ── 2. Escribir registro ──────────────────────────────────
                    when ST_CFG_WR_FILL =>
                        if s_i2c_wr_full = '0' then
                            s_i2c_wr_data <= c_CFG_TABLE(s_cfg_idx).data;
                            s_i2c_wr_push <= '1';
                            s_state       <= ST_CFG_WR_START;
                        end if;

                    when ST_CFG_WR_START =>
                        if s_i2c_busy = '0' and s_i2c_rd_empty = '1' then
                            s_i2c_rw       <= '0';
                            s_i2c_addr_reg <= c_CFG_TABLE(s_cfg_idx).addr;
                            s_i2c_num_regs <= 1;
                            s_i2c_start    <= '1';
                            s_state        <= ST_CFG_WR_WAIT;
                        end if;

                    when ST_CFG_WR_WAIT =>
                        if s_i2c_error = '1' then
                            s_state <= ST_ERROR;
                        elsif s_i2c_done = '1' then
                            s_state <= ST_CFG_RD_START;
                        end if;

                    -- ── 3. Readback (verify) ──────────────────────────────────
                    when ST_CFG_RD_START =>
                        if s_i2c_busy = '0' and s_i2c_rd_empty = '1' then
                            s_i2c_rw       <= '1';
                            s_i2c_addr_reg <= c_CFG_TABLE(s_cfg_idx).addr;
                            s_i2c_num_regs <= 1;
                            s_i2c_start    <= '1';
                            s_state        <= ST_CFG_RD_WAIT;
                        end if;

                    when ST_CFG_RD_WAIT =>
                        if s_i2c_error = '1' then
                            s_state <= ST_ERROR;
                        elsif s_i2c_done = '1' then
                            s_state <= ST_CFG_RD_DRAIN;
                        end if;

                    -- ── 4. Verificar readback ─────────────────────────────────
                    when ST_CFG_RD_DRAIN =>
                        if s_i2c_rd_empty = '0' then
                            s_i2c_rd_pop <= '1';
                            if s_i2c_rd_data = c_CFG_TABLE(s_cfg_idx).data then
                                s_state <= ST_CFG_NEXT;
                            else
                                s_state <= ST_ERROR;  --! Verify fallido
                            end if;
                        end if;

                    -- ── 5. Avanzar o terminar ─────────────────────────────────
                    when ST_CFG_NEXT =>
                        if s_cfg_idx = c_CFG_TABLE_LEN - 1 then
                            s_state <= ST_FINISH;
                        else
                            s_cfg_idx <= s_cfg_idx + 1;
                            s_state   <= ST_CFG_PAGE_FILL;
                        end if;

                    -- ── Estados finales ───────────────────────────────────────
                    when ST_FINISH =>
                        basys3_led_o(0) <= '1';
                        basys3_led_o(1) <= '0';
                        -- Procesar comandos recibidos del PC
                        -- CMD 0x01 (LED): toggle LED 15
                        if s_cmd_valid_sync1 = '1' and s_cmd_type_sync1 = x"01" then
                            s_led15_r <= not s_led15_r;
                        end if;
                        s_state <= ST_FINISH;

                    when ST_ERROR =>
                        basys3_led_o(0) <= '0';
                        basys3_led_o(1) <= '1';
                        s_state <= ST_ERROR;

                    when others =>
                        s_state <= ST_CAM_RESET_ASSERT;

                end case;
            end if;
        end if;
    end process p_fsm;

    basys3_led_o(14 downto 2) <= basys3_sw_i(14 downto 2);  --! LEDs 14:2 reflejan switches
    basys3_led_o(15)          <= s_led15_r;                  --! LED 15 controlado por comando toggle desde PC

    ---------------------------------------------------------------------------
    -- IPs Xilinx
    ---------------------------------------------------------------------------
    u_MMCM : entity work.clk_wiz_0
        port map (
            clk_in1  => basys3_clk_i,
            reset    => basys3_btn_i(c_BASYS3_BTN_CENTER),
            clk_out1 => s_mclk,
            clk_out2 => cam_mclk_r,
            locked   => s_locked
        );

    u_async_fifo : entity work.fifo_generator_0
        port map (
            wr_clk => s_mt_pixclk_int,
            din    => s_cap_fifo_data,
            wr_en  => s_cap_fifo_wr,
            full   => s_cap_fifo_full,
            rd_clk => s_ftdi_clk,
            dout   => s_cap_fifo_dout,
            rd_en  => s_cap_fifo_rd_en,
            empty  => s_cap_fifo_empty,
            rst    => s_rst_final
        );

    g_ila_on : if g_USE_ILA generate
        u_ila : entity work.ila_0
            port map (
                clk       => s_ftdi_clk,
                probe0    => s_cap_fifo_dout,
                probe1(0) => s_ftdi_rxf_n,   --! RXF# — '0' cuando hay dato del PC disponible
                probe2(0) => s_ftdi_rd_n,    --! RD#  — '0' cuando la FPGA está leyendo
                probe3(0) => s_ftdi_wr_n,
                probe4(0) => s_ftdi_txe_n
            );
        u_ila_1 : entity work.ila_0
            port map (
                clk       => s_mclk,
                probe0    => debug_dout,
                probe1(0) => debug_overflow,
                probe2(0) => debug_fval,
                probe3(0) => debug_lval,
                probe4(0) => s_cap_fifo_wr
            );
    end generate;


    u_ila_ftdi : entity work.ila_2
    port map (
        clk       => s_ftdi_clk,
        probe0(0) => s_ftdi_rxf_n,
        probe1(0) => s_ftdi_txe_n,
        probe2(0) => s_ftdi_rd_n,
        probe3    => s_ftdi_adbus_in,   -- 8 bits
        probe4(0) => s_ftdi_wr_n,
        probe5(0) => s_ftdi_oe_n,
        probe6(0) => s_ftdi_adbus_oe,
        probe7(0) => s_ftdi_tx_active,
        probe8(0) => s_cmd_valid_ftdi,
        probe9    => s_cmd_type_ftdi    -- 8 bits
    );

    ---------------------------------------------------------------------------
    -- Módulos propios
    ---------------------------------------------------------------------------
    u_frame_capture : entity work.frame_capture
        generic map (
            g_H_RES      => c_CAP_H_RES,
            g_V_RES      => c_CAP_V_RES,
            g_CAM_FPS    => g_MT9V111_FPS,
            g_TARGET_FPS => g_MT9V111_TARGET_FPS
        )
        port map (
            pixclk_i     => s_mt_pixclk_int,
            reset_i      => s_rst_final,
            fvalid_i     => s_mt_fvalid_int,
            lvalid_i     => s_mt_lvalid_int,
            data_i       => s_mt_data_int,
            capture_en_i => s_cap_en,
            fifo_data_o  => s_cap_fifo_data,
            fifo_wr_o    => s_cap_fifo_wr,
            fifo_full_i  => s_cap_fifo_full,
            frame_done_o => s_cap_frame_done,
            overflow_o   => s_cap_overflow
        );

    u_ftdi_ctrl : entity work.ftdi_controller
        port map (
            clk_i        => s_ftdi_clk,
            reset_i      => s_rst_final,
            fifo_data_i  => s_cap_fifo_dout,
            fifo_empty_i => s_cap_fifo_empty,
            fifo_rd_en_o => s_cap_fifo_rd_en,
            rxf_n_i      => s_ftdi_rxf_n,       --! RXF# — dato disponible del PC
            txe_n_i      => s_ftdi_txe_n,
            rd_n_o       => s_ftdi_rd_n,         --! RD#  — strobe lectura
            wr_n_o       => s_ftdi_wr_n,
            oe_n_o       => s_ftdi_oe_n,         --! OE#  — habilita FTDI en ADBUS
            adbus_i      => s_ftdi_adbus_in,     --! ADBUS entrada (comandos del PC)
            adbus_o      => s_ftdi_adbus_out,    --! ADBUS salida  (imagen hacia PC)
            adbus_oe     => s_ftdi_adbus_oe,     --! Dirección del tristate
            tx_active_o  => s_ftdi_tx_active,
            cmd_valid_o  => s_cmd_valid_ftdi,    --! Pulso 1 ciclo: comando decodificado listo
            cmd_type_o   => s_cmd_type_ftdi,     --! Tipo de comando
            cmd_data_o   => s_cmd_data_ftdi,     --! Payload del comando
            cmd_page_o   => s_cmd_page_ftdi,     --! Page (solo CMD I2C)
            cmd_addr_o   => s_cmd_addr_ftdi      --! Addr  (solo CMD I2C)
        );

    u_i2c : entity work.i2c_master
        generic map (
            g_CLK_FREQ_HZ => g_SYSTEM_CLK_FREQ_HZ,
            g_I2C_FREQ_HZ => g_MT9V111_I2C_FREQ_HZ,
            g_FIFO_DEPTH  => g_MT9V111_I2C_FIFO_DEPTH
        )
        port map (
            clk_i           => s_mclk,
            reset_i         => s_rst_final,
            rw_i            => s_i2c_rw,
            start_i2c_i     => s_i2c_start,
            num_regs_i      => s_i2c_num_regs,
            addr_dev_i      => g_MT9V111_I2C_SENSOR_ADDR,
            addr_reg_i      => s_i2c_addr_reg,
            wr_fifo_push_i  => s_i2c_wr_push,
            wr_fifo_data_i  => s_i2c_wr_data,
            wr_fifo_full_o  => s_i2c_wr_full,
            wr_fifo_empty_o => s_i2c_wr_empty,
            rd_fifo_pop_i   => s_i2c_rd_pop,
            rd_fifo_data_o  => s_i2c_rd_data,
            rd_fifo_full_o  => s_i2c_rd_full,
            rd_fifo_empty_o => s_i2c_rd_empty,
            busy_o          => s_i2c_busy,
            done_o          => s_i2c_done,
            error_o         => s_i2c_error,
            scl_o           => s_scl_out,
            sda_o           => s_sda_out,
            sda_oe_o        => s_sda_oe,
            sda_i           => s_sda_in
        );

    ---------------------------------------------------------------------------
    -- Selección de fuente de imagen
    ---------------------------------------------------------------------------
    g_real_image : if not g_USE_CAM_SIM generate
        s_mt_fvalid_int <= mt_fvalid_i;
        s_mt_lvalid_int <= mt_lvalid_i;
        s_mt_data_int   <= mt_data_i;
        s_mt_pixclk_int <= mt_pixclk_i;
    end generate;

    g_cam_sim_on : if g_USE_CAM_SIM generate
        u_cam_sim : entity work.mt9v111_image
            generic map (
                g_H_RES  => g_CAM_SIM_H_RES,
                g_V_RES  => g_CAM_SIM_V_RES,
                g_HBLANK => g_CAM_SIM_HBLANK,
                g_VBLANK => g_CAM_SIM_VBLANK
            )
            port map (
                clkin_i  => cam_mclk_r,
                pixclk_o => s_mt_pixclk_int,
                reset_i  => s_rst_final,
                fvalid_o => s_mt_fvalid_int,
                lvalid_o => s_mt_lvalid_int,
                data_o   => s_mt_data_int
            );
    end generate;
end architecture rtl;