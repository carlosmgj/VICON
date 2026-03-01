--! \file TOP.vhd
--! Archivo fuente VHDL para el controlador a desarrollar.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TOP is
    generic (
        CLK_FREQ_HZ  : integer := 50_000_000;
        I2C_FREQ_HZ  : integer := 400_000;
        FIFO_DEPTH   : integer := 16;
        SENSOR_ADDR  : std_logic_vector(6 downto 0) := "1011100"  -- 0x5C
    );
    port (
        clk   : in    std_logic;
        reset : in    std_logic;
        sclk  : out   std_logic;
        sdata : inout std_logic;
        done  : out   std_logic
    );
end entity TOP;

architecture Behavioral of TOP is

    ---------------------------------------------------------------------------
    -- Señales hacia/desde i2c_master
    ---------------------------------------------------------------------------
    -- Control
    signal i2c_rw        : std_logic := '0';
    signal i2c_start     : std_logic := '0';
    signal i2c_num_regs  : integer range 1 to FIFO_DEPTH := 1;
    signal i2c_addr_reg  : std_logic_vector(7 downto 0)  := (others => '0');

    -- WR FIFO
    signal i2c_wr_push   : std_logic := '0';
    signal i2c_wr_data   : std_logic_vector(15 downto 0) := (others => '0');
    signal i2c_wr_full   : std_logic;
    signal i2c_wr_empty  : std_logic;

    -- RD FIFO
    signal i2c_rd_pop    : std_logic := '0';
    signal i2c_rd_data   : std_logic_vector(15 downto 0);
    signal i2c_rd_full   : std_logic;
    signal i2c_rd_empty  : std_logic;

    -- Estado
    signal i2c_busy      : std_logic;
    signal i2c_done      : std_logic;
    signal i2c_error     : std_logic;

    ---------------------------------------------------------------------------
    -- FSM del TOP
    --
    -- Secuencia de ejemplo:
    --   1. Escribir 2 registros consecutivos a partir de addr_reg=0x04
    --      (aprovechando auto-increment del MT9V111)
    --   2. Leer 2 registros consecutivos a partir de addr_reg=0x04
    --   3. Vaciar RD_FIFO y señalizar done
    ---------------------------------------------------------------------------
    type main_state_t is (
        ST_IDLE,
        -- Escritura
        ST_WR_FILL_FIFO,    -- Cargar datos en WR FIFO
        ST_WR_START,        -- Lanzar transacción write
        ST_WR_WAIT,         -- Esperar done/error
        -- Lectura
        ST_RD_START,        -- Lanzar transacción read
        ST_RD_WAIT,         -- Esperar done/error
        ST_RD_DRAIN,        -- Vaciar RD FIFO (procesar datos leídos)
        -- Fin
        ST_FINISH,
        ST_ERROR
    );
    signal state : main_state_t := ST_IDLE;

    -- Contador para cargar múltiples entradas en la WR FIFO
    signal fill_cnt : integer range 0 to FIFO_DEPTH := 0;

    -- Número de registros a escribir/leer en este ejemplo
    constant NUM_REGS_WR : integer := 2;
    constant NUM_REGS_RD : integer := 2;

    -- Datos de ejemplo a escribir (se pueden sustituir por señales externas)
    type reg_data_array_t is array (0 to NUM_REGS_WR - 1) of std_logic_vector(15 downto 0);
    constant WR_DATA : reg_data_array_t := (
        0 => x"823A",   -- Reg 0x04
        1 => x"0010"    -- Reg 0x05 (auto-increment)
    );

    -- Buffer para almacenar los registros leídos
    type rd_buf_t is array (0 to NUM_REGS_RD - 1) of std_logic_vector(15 downto 0);
    signal rd_buf   : rd_buf_t := (others => (others => '0'));
    signal rd_cnt   : integer range 0 to NUM_REGS_RD := 0;

begin

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
            clk           => clk,
            reset         => reset,
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
            sclk          => sclk,
            sdata         => sdata
        );

    ---------------------------------------------------------------------------
    -- FSM principal
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
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
                done         <= '0';
            else
                -- Pulsos de un ciclo por defecto
                i2c_start   <= '0';
                i2c_wr_push <= '0';
                i2c_rd_pop  <= '0';

                case state is

                    -----------------------------------------------------------
                    when ST_IDLE =>
                        done     <= '0';
                        fill_cnt <= 0;
                        rd_cnt   <= 0;
                        state    <= ST_WR_FILL_FIFO;

                    -----------------------------------------------------------
                    -- Cargar datos en WR FIFO antes de lanzar la escritura.
                    -- Se comprueban dos condiciones: FIFO no llena y aún
                    -- quedan datos por meter.
                    -----------------------------------------------------------
                    when ST_WR_FILL_FIFO =>
                        if fill_cnt = NUM_REGS_WR then
                            -- FIFO cargada → lanzar escritura
                            fill_cnt <= 0;
                            state    <= ST_WR_START;
                        elsif i2c_wr_full = '0' then
                            i2c_wr_data  <= WR_DATA(fill_cnt);
                            i2c_wr_push  <= '1';
                            fill_cnt     <= fill_cnt + 1;
                        end if;
                        -- Si FIFO llena y aún quedan datos: esperar (raro con
                        -- FIFO_DEPTH >= NUM_REGS_WR, pero seguro)

                    -----------------------------------------------------------
                    when ST_WR_START =>
                        if i2c_busy = '0' then
                            i2c_rw       <= '0';           -- Write
                            i2c_addr_reg <= x"04";         -- Registro inicial
                            i2c_num_regs <= NUM_REGS_WR;
                            i2c_start    <= '1';
                            state        <= ST_WR_WAIT;
                        end if;

                    -----------------------------------------------------------
                    when ST_WR_WAIT =>
                        if i2c_error = '1' then
                            state <= ST_ERROR;
                        elsif i2c_done = '1' then
                            state <= ST_RD_START;
                        end if;

                    -----------------------------------------------------------
                    when ST_RD_START =>
                        -- El controlador bloquea si RD FIFO no está vacía,
                        -- pero aquí sabemos que lo está (acabamos de arrancar)
                        if i2c_busy = '0' and i2c_rd_empty = '1' then
                            i2c_rw       <= '1';           -- Read
                            i2c_addr_reg <= x"04";
                            i2c_num_regs <= NUM_REGS_RD;
                            i2c_start    <= '1';
                            state        <= ST_RD_WAIT;
                        end if;

                    -----------------------------------------------------------
                    when ST_RD_WAIT =>
                        if i2c_error = '1' then
                            state <= ST_ERROR;
                        elsif i2c_done = '1' then
                            rd_cnt <= 0;
                            state  <= ST_RD_DRAIN;
                        end if;

                    -----------------------------------------------------------
                    -- Vaciar RD FIFO y guardar en buffer interno.
                    -- Cada ciclo en que rd_fifo_empty='0' se hace pop.
                    -----------------------------------------------------------
                    when ST_RD_DRAIN =>
                        if i2c_rd_empty = '0' and rd_cnt < NUM_REGS_RD then
                            i2c_rd_pop         <= '1';
                            rd_buf(rd_cnt)     <= i2c_rd_data;
                            rd_cnt             <= rd_cnt + 1;
                        elsif rd_cnt = NUM_REGS_RD then
                            state <= ST_FINISH;
                        end if;

                    -----------------------------------------------------------
                    when ST_FINISH =>
                        done  <= '1';
                        state <= ST_FINISH;  -- Mantener done='1'
                        -- Aquí rd_buf(0) y rd_buf(1) tienen los valores leídos

                    -----------------------------------------------------------
                    when ST_ERROR =>
                        done  <= '0';
                        state <= ST_ERROR;
                        -- Señal de error visible en i2c_error del controlador.
                        -- Añadir lógica de recuperación si es necesario.

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture Behavioral;