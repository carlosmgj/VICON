--! \file TOP.vhd
--! \brief Top-level del sistema de comunicación con la cámara MT9V111.
--!
--! Secuencia de ejemplo al arrancar:
--!   1. Escribe 2 registros a partir de REG 0x04 (auto-increment)
--!   2. Lee 2 registros a partir de REG 0x04
--!   3. LED(0) = '1' si todo OK, se queda en ST_ERROR si hubo NACK
--!
--! Notas de hardware (Basys 3):
--!   - sclk y sdata son open-drain: la FPGA solo fuerza '0'; el pull-up
--!     externo (típicamente 4.7kΩ) lleva la línea a '1' cuando está en 'Z'.
--!   - El MMCM genera mclk a partir del oscilador de 100 MHz de la placa.
--!   - BTN(0) resetea el MMCM; el sistema sale de reset cuando locked='1'.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TOP is
    generic (
        CLK_FREQ_HZ : integer                       := 100_000_000;    --! Frecuencia de mclk (Hz)
        I2C_FREQ_HZ : integer                       := 400_000;         --! Frecuencia I2C deseada (Hz)
        FIFO_DEPTH  : integer                       := 16;              --! Profundidad de las FIFOs
        SENSOR_ADDR : std_logic_vector(6 downto 0) := "1011100"         --! Dirección I2C del MT9V111 (0x5C)
    );
    port (
        clk   : in    std_logic;                        --! Oscilador 100 MHz de la Basys 3
        BTN   : in    std_logic_vector(4 downto 0);     --! BTN(0) = reset del MMCM
        SW    : in    std_logic_vector(15 downto 0);
        LED   : out   std_logic_vector(15 downto 0);    --! LED(0) = done
        CAT   : out   std_logic_vector(7 downto 0);     --! Display de 7 segmentos (no usado)
        AN    : out   std_logic_vector(3 downto 0);     --! Anodos display (no usado)
        sclk  : inout std_logic;                        --! I2C SCL (open-drain)
        sdata : inout std_logic                         --! I2C SDA (open-drain)
    );
end entity TOP;

architecture Behavioral of TOP is

    ---------------------------------------------------------------------------
    -- Reloj y reset
    ---------------------------------------------------------------------------
    signal mclk      : std_logic;
    signal locked    : std_logic;
    signal rst_final : std_logic;  --! Reset activo alto; '1' hasta que el MMCM esté estable

    ---------------------------------------------------------------------------
    -- Señales de interfaz con i2c_master — Control
    ---------------------------------------------------------------------------
    signal i2c_rw       : std_logic                              := '0';
    signal i2c_start    : std_logic                              := '0';
    signal i2c_num_regs : integer range 1 to FIFO_DEPTH         := 1;
    signal i2c_addr_reg : std_logic_vector(7 downto 0)          := (others => '0');

    ---------------------------------------------------------------------------
    -- Señales de interfaz con i2c_master — WR FIFO
    ---------------------------------------------------------------------------
    signal i2c_wr_push  : std_logic                              := '0';
    signal i2c_wr_data  : std_logic_vector(15 downto 0)         := (others => '0');
    signal i2c_wr_full  : std_logic;
    signal i2c_wr_empty : std_logic;

    ---------------------------------------------------------------------------
    -- Señales de interfaz con i2c_master — RD FIFO
    ---------------------------------------------------------------------------
    signal i2c_rd_pop   : std_logic                              := '0';
    signal i2c_rd_data  : std_logic_vector(15 downto 0);
    signal i2c_rd_full  : std_logic;
    signal i2c_rd_empty : std_logic;

    ---------------------------------------------------------------------------
    -- Señales de interfaz con i2c_master — Estado
    ---------------------------------------------------------------------------
    signal i2c_busy     : std_logic;
    signal i2c_done     : std_logic;
    signal i2c_error    : std_logic;

    ---------------------------------------------------------------------------
    -- Señales de interfaz con i2c_master — Bus (separadas del inout físico)
    -- El tristate y open-drain se manejan aquí en el TOP.
    ---------------------------------------------------------------------------
    signal scl_out_i  : std_logic;  --! Valor que el controlador quiere poner en SCL
    signal sda_out_i  : std_logic;  --! Valor que el controlador quiere poner en SDA
    signal sda_oe_i   : std_logic;  --! '1'=conducir SDA  '0'=tristate
    signal sda_in_i   : std_logic;  --! Valor leído del bus SDA

    ---------------------------------------------------------------------------
    -- FSM del TOP
    ---------------------------------------------------------------------------
    type main_state_t is (
        ST_IDLE,
        ST_WR_FILL_FIFO,    --! Cargar datos en WR FIFO
        ST_WR_START,        --! Lanzar transacción Write
        ST_WR_WAIT,         --! Esperar done/error del Write
        ST_RD_START,        --! Lanzar transacción Read
        ST_RD_WAIT,         --! Esperar done/error del Read
        ST_RD_DRAIN,        --! Vaciar RD FIFO
        ST_FINISH,          --! Transacción completada correctamente
        ST_ERROR            --! Error (NACK u otro)
    );
    signal state : main_state_t := ST_IDLE;

    signal fill_cnt : integer range 0 to FIFO_DEPTH := 0;  --! Contador de llenado de WR FIFO
    signal rd_cnt   : integer range 0 to 16          := 0;  --! Contador de vaciado de RD FIFO

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
    signal rd_buf : rd_buf_t := (others => (others => '0'));  --! Buffer de datos leídos

    ---------------------------------------------------------------------------
    -- ILA / Debug
    -- debug_sclk y debug_sdata capturan lo que el controlador pone en el bus,
    -- no el pin físico (que puede estar en 'Z' cuando open-drain).
    ---------------------------------------------------------------------------
    signal debug_sclk  : std_logic;
    signal debug_sdata : std_logic;

    attribute mark_debug : string;
    attribute mark_debug of i2c_start  : signal is "true";
    attribute mark_debug of i2c_busy   : signal is "true";
    attribute mark_debug of i2c_done   : signal is "true";
    attribute mark_debug of i2c_error  : signal is "true";
    attribute mark_debug of debug_sclk : signal is "true";
    attribute mark_debug of debug_sdata: signal is "true";

begin

    ---------------------------------------------------------------------------
    -- Bus I2C — open-drain
    -- SCL: la FPGA solo fuerza '0'; el pull-up externo da el '1'.
    -- SDA: igual, controlado por sda_oe_i.
    ---------------------------------------------------------------------------
    sclk     <= '0' when scl_out_i = '0' else 'Z';
    sdata    <= sda_out_i when sda_oe_i = '1' else 'Z';
    sda_in_i <= sdata;

    ---------------------------------------------------------------------------
    -- Debug: captura registrada de lo que el controlador pone en el bus
    ---------------------------------------------------------------------------
    p_debug : process(mclk)
    begin
        if rising_edge(mclk) then
            debug_sclk  <= scl_out_i;  --! Lo que el controlador intenta poner en SCL
            debug_sdata <= sda_in_i;   --! Lo que hay en el bus SDA (incluye lo que pone el esclavo)
        end if;
    end process p_debug;

    ---------------------------------------------------------------------------
    -- Salidas no usadas
    ---------------------------------------------------------------------------
    CAT <= (others => '0');
    AN  <= (others => '1');  -- Anodos activos bajos: '1' = display apagado

    ---------------------------------------------------------------------------
    -- MMCM
    -- BTN(0) resetea el MMCM. El sistema sale de reset cuando locked='1'.
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
            -- Control
            rw            => i2c_rw,
            start_i2c     => i2c_start,
            num_regs      => i2c_num_regs,
            addr_dev      => SENSOR_ADDR,
            addr_reg      => i2c_addr_reg,
            -- WR FIFO
            wr_fifo_push  => i2c_wr_push,
            wr_fifo_data  => i2c_wr_data,
            wr_fifo_full  => i2c_wr_full,
            wr_fifo_empty => i2c_wr_empty,
            -- RD FIFO
            rd_fifo_pop   => i2c_rd_pop,
            rd_fifo_data  => i2c_rd_data,
            rd_fifo_full  => i2c_rd_full,
            rd_fifo_empty => i2c_rd_empty,
            -- Estado
            busy          => i2c_busy,
            done          => i2c_done,
            error         => i2c_error,
            -- Bus
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
                state        <= ST_IDLE;
                i2c_rw       <= '0';
                i2c_start    <= '0';
                i2c_wr_push  <= '0';
                i2c_rd_pop   <= '0';
                i2c_num_regs <= 1;
                i2c_addr_reg <= (others => '0');
                i2c_wr_data  <= (others => '0');
                fill_cnt     <= 0;
                rd_cnt       <= 0;
                LED(0)       <= '0';
            else
                -- Pulsos de un ciclo por defecto
                i2c_start   <= '0';
                i2c_wr_push <= '0';
                i2c_rd_pop  <= '0';

                case state is

                    when ST_IDLE =>
                        LED(0)   <= '0';
                        fill_cnt <= 0;
                        rd_cnt   <= 0;
                        state    <= ST_WR_FILL_FIFO;

                    -----------------------------------------------------------
                    -- Cargar WR FIFO antes de lanzar la escritura
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
                    -- Vaciar RD FIFO y guardar en buffer interno
                    -----------------------------------------------------------
                    when ST_RD_DRAIN =>
                        if i2c_rd_empty = '0' and rd_cnt < NUM_REGS_RD then
                            i2c_rd_pop     <= '1';
                            rd_buf(rd_cnt) <= i2c_rd_data;
                            rd_cnt         <= rd_cnt + 1;
                        elsif rd_cnt = NUM_REGS_RD then
                            state <= ST_FINISH;
                        end if;

                    when ST_FINISH =>
                        LED(0) <= '1';          --! Indica éxito
                        state  <= ST_FINISH;    --! rd_buf(0) y rd_buf(1) contienen los datos leídos

                    when ST_ERROR =>
                        LED(0) <= '0';
                        state  <= ST_ERROR;

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

    ---------------------------------------------------------------------------
    -- LEDs auxiliares
    ---------------------------------------------------------------------------
    LED(15 downto 1) <= SW(15 downto 1);

end architecture Behavioral;
