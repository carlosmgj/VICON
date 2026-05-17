--! \file TOP.vhd
--! \brief Top-level del sistema de comunicación con la cámara MT9V111.
--!
--! Secuencia de inicialización al arrancar:
--!   1. ST_CAM_RESET_ASSERT : RESET_BAR='0' durante 1 ms
--!   2. ST_CAM_RESET_WAIT   : RESET_BAR='1', espera 150 ms para que la cámara arranque
--!   3. ST_WR_FILL_FIFO     : Cargar WR FIFO
--!   4. ST_WR_START/WAIT    : Escribir registros por I2C
--!   5. ST_RD_START/WAIT    : Leer registros por I2C
--!   6. ST_RD_DRAIN         : Vaciar RD FIFO
--!   7. ST_FINISH           : LED(0)='1' OK, LED(1)='1' error
--!
--! Notas de hardware (Basys 3):
--!   - sclk y sdata son open-drain. Necesitan pull-ups externos de 4.7 kΩ a 3.3 V.
--!   - cam_mclk se genera dividiendo mclk por 4 → 25 MHz (rango válido: 13-27 MHz).
--!   - cam_reset_n es activo bajo. La FSM lo controla con un contador de tiempo.
--!   - BTN(0) resetea el MMCM y reinicia toda la secuencia.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TOP is
    generic (
        CLK_FREQ_HZ  : integer                       := 100_000_000;  --! Frecuencia de mclk (Hz)
        I2C_FREQ_HZ  : integer                       := 400_000;       --! Frecuencia I2C (Hz)
        FIFO_DEPTH   : integer                       := 16;            --! Profundidad de las FIFOs
        SENSOR_ADDR  : std_logic_vector(6 downto 0) := "1011100"       --! Dirección I2C MT9V111 (0x5C)
    );
    port (
        -- System CLK 
        clk         : in    std_logic;                     --! Oscilador 100 MHz de la Basys 3
        -- Dev Board interface 
        SW          : in    std_logic_vector(15 downto 0);
        LED         : out   std_logic_vector(15 downto 0); --! LED(0)=OK  LED(1)=error
        CAT         : out   std_logic_vector(6 downto 0);
        DP          : out   std_logic;
        AN          : out   std_logic_vector(3 downto 0);
        BTN         : in    std_logic_vector(4 downto 0);  --! BTN(0) = reset del MMCM
        -- MT9V111 - JA & JXADC
        dout        : in    std_logic_vector(7 downto 0);
        line_valid  : in    std_logic;
        pixclk      : in    std_logic;
        cam_reset_n : out   std_logic;                     --! RESET_BAR de la cámara (activo bajo)
        sclk        : inout std_logic;                     --! I2C SCL (open-drain)
        sdata       : inout std_logic;                     --! I2C SDA (open-drain)
        frame_valid : in    std_logic;
        cam_mclk    : out   std_logic                      --! Master clock de la cámara (~25 MHz)
    );
end entity TOP;

architecture Behavioral of TOP is

    ---------------------------------------------------------------------------
    -- Constantes de temporización de inicialización
    ---------------------------------------------------------------------------
    constant RESET_HOLD_CYCLES : integer := CLK_FREQ_HZ / 1000;        --!   1 ms a 100 MHz
    constant RESET_WAIT_CYCLES : integer := CLK_FREQ_HZ / 1000 * 150;  --! 150 ms a 100 MHz
    constant MCLK_DIV          : integer := 2;  --! Toggle cada 2 ciclos → 25 MHz

    ---------------------------------------------------------------------------
    -- Reloj y reset
    ---------------------------------------------------------------------------
    signal mclk      : std_logic;
    signal locked    : std_logic;
    signal rst_final : std_logic;  --! Activo alto; '1' hasta que el MMCM esté estable

    ---------------------------------------------------------------------------
    -- Generación de MCLK para la cámara (25 MHz = mclk/4)
    ---------------------------------------------------------------------------
    signal mclk_div_cnt : integer range 0 to MCLK_DIV - 1 := 0;
    signal cam_mclk_r   : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Interfaz con i2c_master — Control
    ---------------------------------------------------------------------------
    signal i2c_rw       : std_logic                      := '0';
    signal i2c_start    : std_logic                      := '0';
    signal i2c_num_regs : integer range 1 to FIFO_DEPTH := 1;
    signal i2c_addr_reg : std_logic_vector(7 downto 0)  := (others => '0');

    ---------------------------------------------------------------------------
    -- Interfaz con i2c_master — WR FIFO
    ---------------------------------------------------------------------------
    signal i2c_wr_push  : std_logic                      := '0';
    signal i2c_wr_data  : std_logic_vector(15 downto 0) := (others => '0');
    signal i2c_wr_full  : std_logic;
    signal i2c_wr_empty : std_logic;

    ---------------------------------------------------------------------------
    -- Interfaz con i2c_master — RD FIFO
    ---------------------------------------------------------------------------
    signal i2c_rd_pop   : std_logic                      := '0';
    signal i2c_rd_data  : std_logic_vector(15 downto 0);
    signal i2c_rd_full  : std_logic;
    signal i2c_rd_empty : std_logic;

    ---------------------------------------------------------------------------
    -- Interfaz con i2c_master — Estado
    ---------------------------------------------------------------------------
    signal i2c_busy  : std_logic;
    signal i2c_done  : std_logic;
    signal i2c_error : std_logic;

    ---------------------------------------------------------------------------
    -- Interfaz con i2c_master — Bus (señales separadas del inout físico)
    ---------------------------------------------------------------------------
    signal scl_out_i : std_logic;
    signal sda_out_i : std_logic;
    signal sda_oe_i  : std_logic;
    signal sda_in_i  : std_logic;

    ---------------------------------------------------------------------------
    -- FSM del TOP
    ---------------------------------------------------------------------------
    type main_state_t is (
        ST_CAM_RESET_ASSERT,    --! RESET_BAR='0' durante RESET_HOLD_CYCLES
        ST_CAM_RESET_WAIT,      --! Espera 150 ms tras soltar el reset
        ST_WR_FILL_FIFO,        --! Cargar datos en WR FIFO
        ST_WR_START,            --! Lanzar transacción Write
        ST_WR_WAIT,             --! Esperar done/error del Write
        ST_RD_START,            --! Lanzar transacción Read
        ST_RD_WAIT,             --! Esperar done/error del Read
        ST_RD_DRAIN,            --! Vaciar RD FIFO
        ST_FINISH,
        ST_ERROR
    );
    signal state : main_state_t := ST_CAM_RESET_ASSERT;

    signal init_cnt    : integer range 0 to RESET_WAIT_CYCLES := 0;
    signal fill_cnt    : integer range 0 to FIFO_DEPTH        := 0;
    signal rd_cnt      : integer range 0 to 16               := 0;
    signal cam_reset_r : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Datos de ejemplo
    ---------------------------------------------------------------------------
    constant NUM_REGS_WR : integer := 2;
    constant NUM_REGS_RD : integer := 2;

    type reg_data_array_t is array (0 to NUM_REGS_WR - 1) of std_logic_vector(15 downto 0);
    constant WR_DATA : reg_data_array_t := (
        0 => x"823A",   --! Reg 0x04
        1 => x"0010"    --! Reg 0x05 (auto-increment)
    );

    type rd_buf_t is array (0 to NUM_REGS_RD - 1) of std_logic_vector(15 downto 0);
    signal rd_buf : rd_buf_t := (others => (others => '0'));

    ---------------------------------------------------------------------------
    -- ILA / Debug
    ---------------------------------------------------------------------------
    signal debug_sclk  : std_logic;
    signal debug_sdata : std_logic;
    signal debug_mclk : std_logic;
    signal debug_dout       : std_logic_vector(7 downto 0);
    signal debug_pixclk     : std_logic;
    signal debug_fval       : std_logic;
    signal debug_lval       : std_logic;
    
    attribute mark_debug : string;
    attribute dont_touch : string;

    attribute mark_debug of i2c_start    : signal is "true";
    attribute mark_debug of i2c_busy     : signal is "true";
    attribute mark_debug of i2c_done     : signal is "true";
    attribute mark_debug of i2c_error    : signal is "true";
    attribute mark_debug of debug_sclk   : signal is "true";
    attribute mark_debug of debug_sdata  : signal is "true";
    attribute mark_debug of state        : signal is "true";
    attribute mark_debug of cam_reset_r  : signal is "true";
    attribute mark_debug of cam_mclk_r   : signal is "true";
    attribute dont_touch of cam_mclk_r   : signal is "true";
    attribute mark_debug of debug_dout   : signal is "true";
    attribute mark_debug of debug_pixclk : signal is "true";
    attribute mark_debug of debug_fval   : signal is "true";
    attribute mark_debug of debug_lval   : signal is "true";


begin

    ---------------------------------------------------------------------------
    -- Bus I2C — open-drain
    ---------------------------------------------------------------------------
    sclk     <= '0' when scl_out_i = '0' else 'Z';
    sdata    <= sda_out_i when sda_oe_i = '1' else 'Z';
    sda_in_i <= sdata;

    ---------------------------------------------------------------------------
    -- Señales de cámara
    ---------------------------------------------------------------------------
    cam_reset_n <= cam_reset_r;
    cam_mclk    <= cam_mclk_r;

    ---------------------------------------------------------------------------
    -- Salidas no usadas
    ---------------------------------------------------------------------------
    CAT <= (others => '0');
    DP  <= '0';
    AN  <= (others => '1');  --! Ánodos activos bajos: '1' = display apagado

    p_debug : process(mclk)
    begin
        if rising_edge(mclk) then
            debug_sclk  <= scl_out_i;
            debug_sdata <= sda_in_i;
            debug_dout       <= dout;
            debug_pixclk     <= pixclk;
            debug_fval       <= frame_valid;
            debug_lval       <= line_valid;
        end if;
    end process p_debug;

    ---------------------------------------------------------------------------
    -- Generación de MCLK para la cámara
    -- Toggle cada MCLK_DIV ciclos → 100 MHz / 4 = 25 MHz
    ---------------------------------------------------------------------------
    p_cam_mclk : process(mclk)
    begin
        if rising_edge(mclk) then
            if rst_final = '1' then
                mclk_div_cnt <= 0;
                cam_mclk_r   <= '0';
            elsif mclk_div_cnt = MCLK_DIV - 1 then
                mclk_div_cnt <= 0;
                cam_mclk_r   <= not cam_mclk_r;
            else
                mclk_div_cnt <= mclk_div_cnt + 1;
            end if;
        end if;
    end process p_cam_mclk;

    ---------------------------------------------------------------------------
    -- MMCM
    ---------------------------------------------------------------------------
    mi_MMCM : entity work.clk_wiz_0
        port map (
            clk_in1  => clk,
            reset    => BTN(0),
            clk_out1 => mclk,
            locked   => locked
        );

    rst_final <= not locked;

    ---------------------------------------------------------------------------
    -- Instancia del controlador I2C
    ---------------------------------------------------------------------------
    u_i2c : entity work.i2c_master
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            I2C_FREQ_HZ => I2C_FREQ_HZ,
            FIFO_DEPTH  => FIFO_DEPTH
        )
        port map (
            clk           => mclk,
            reset         => rst_final,
            rw            => i2c_rw,
            start_i2c     => i2c_start,
            num_regs      => i2c_num_regs,
            addr_dev      => SENSOR_ADDR,
            addr_reg      => i2c_addr_reg,
            wr_fifo_push  => i2c_wr_push,
            wr_fifo_data  => i2c_wr_data,
            wr_fifo_full  => i2c_wr_full,
            wr_fifo_empty => i2c_wr_empty,
            rd_fifo_pop   => i2c_rd_pop,
            rd_fifo_data  => i2c_rd_data,
            rd_fifo_full  => i2c_rd_full,
            rd_fifo_empty => i2c_rd_empty,
            busy          => i2c_busy,
            done          => i2c_done,
            error         => i2c_error,
            scl_out       => scl_out_i,
            sda_out       => sda_out_i,
            sda_oe_o      => sda_oe_i,
            sda_in        => sda_in_i
        );

    ---------------------------------------------------------------------------
    -- FSM principal
    ---------------------------------------------------------------------------
    p_fsm : process(mclk)
    begin
        if rising_edge(mclk) then
            if rst_final = '1' then
                state        <= ST_CAM_RESET_ASSERT;
                cam_reset_r  <= '0';        --! Mantener cámara en reset
                init_cnt     <= 0;
                i2c_rw       <= '0';
                i2c_start    <= '0';
                i2c_wr_push  <= '0';
                i2c_rd_pop   <= '0';
                i2c_num_regs <= 1;
                i2c_addr_reg <= (others => '0');
                i2c_wr_data  <= (others => '0');
                fill_cnt     <= 0;
                rd_cnt       <= 0;
                LED(0) <= '0';
                LED(1) <= '0';
            else
                i2c_start   <= '0';
                i2c_wr_push <= '0';
                i2c_rd_pop  <= '0';

                case state is

                    -----------------------------------------------------------
                    -- Mantener RESET_BAR='0' durante 1 ms
                    -----------------------------------------------------------
                    when ST_CAM_RESET_ASSERT =>
                        cam_reset_r <= '0';
                        if init_cnt = RESET_HOLD_CYCLES - 1 then
                            init_cnt <= 0;
                            state    <= ST_CAM_RESET_WAIT;
                        else
                            init_cnt <= init_cnt + 1;
                        end if;

                    -----------------------------------------------------------
                    -- Soltar reset y esperar 150 ms
                    -----------------------------------------------------------
                    when ST_CAM_RESET_WAIT =>
                        cam_reset_r <= '1';
                        if init_cnt = RESET_WAIT_CYCLES - 1 then
                            init_cnt <= 0;
                            fill_cnt <= 0;
                            rd_cnt   <= 0;
                            state    <= ST_WR_FILL_FIFO;
                        else
                            init_cnt <= init_cnt + 1;
                        end if;

                    -----------------------------------------------------------
                    -- Cargar WR FIFO
                    -----------------------------------------------------------
                    when ST_WR_FILL_FIFO =>
                        if fill_cnt = NUM_REGS_WR then
                            fill_cnt <= 0;
                            state    <= ST_WR_START;
                        elsif i2c_wr_full = '0' then
                            i2c_wr_data <= WR_DATA(fill_cnt);
                            i2c_wr_push <= '1';
                            fill_cnt    <= fill_cnt + 1;
                        end if;

                    -----------------------------------------------------------
                    -- Lanzar transacción Write
                    -----------------------------------------------------------
                    when ST_WR_START =>
                        if i2c_busy = '0' then
                            i2c_rw       <= '0';
                            i2c_addr_reg <= x"04";
                            i2c_num_regs <= NUM_REGS_WR;
                            i2c_start    <= '1';
                            state        <= ST_WR_WAIT;
                        end if;

                    when ST_WR_WAIT =>
                        if i2c_error = '1' then
                            state <= ST_ERROR;
                        elsif i2c_done = '1' then
                            state <= ST_RD_START;
                        end if;

                    -----------------------------------------------------------
                    -- Lanzar transacción Read
                    -----------------------------------------------------------
                    when ST_RD_START =>
                        if i2c_busy = '0' and i2c_rd_empty = '1' then
                            i2c_rw       <= '1';
                            i2c_addr_reg <= x"04";
                            i2c_num_regs <= NUM_REGS_RD;
                            i2c_start    <= '1';
                            state        <= ST_RD_WAIT;
                        end if;

                    when ST_RD_WAIT =>
                        if i2c_error = '1' then
                            state <= ST_ERROR;
                        elsif i2c_done = '1' then
                            rd_cnt <= 0;
                            state  <= ST_RD_DRAIN;
                        end if;

                    -----------------------------------------------------------
                    -- Vaciar RD FIFO
                    -----------------------------------------------------------
                    when ST_RD_DRAIN =>
                        if i2c_rd_empty = '0' and rd_cnt < NUM_REGS_RD then
                            i2c_rd_pop     <= '1';
                            rd_buf(rd_cnt) <= i2c_rd_data;
                            rd_cnt         <= rd_cnt + 1;
                        elsif rd_cnt = NUM_REGS_RD then
                            state <= ST_FINISH;
                        end if;

                    -----------------------------------------------------------
                    when ST_FINISH =>
                        LED(0) <= '1';       --! Éxito: rd_buf contiene los datos leídos
                        LED(1) <= '0';
                        state  <= ST_FINISH;

                    when ST_ERROR =>
                        LED(0) <= '0';
                        LED(1) <= '1';       --! Error visible en LED(1)
                        state  <= ST_ERROR;

                    when others =>
                        state <= ST_CAM_RESET_ASSERT;

                end case;
            end if;
        end if;
    end process p_fsm;

    LED(15 downto 2) <= SW(15 downto 2);

end architecture Behavioral;
