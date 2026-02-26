--! \file i2c_controller.vhd
--! Controlador I2C para el sensor MT9V111. Implementa una escritura simple a la direcciÃ³n del sensor.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity I2C_CONTROLLER is
    generic (
        CLK_DIV_G : positive := 250  -- Medio periodo I2C en ciclos de clk
    );
    port (
        clk      : in    std_logic;
        reset    : in    std_logic;
        -- Control de operación
        rw       : in    std_logic;                      -- '0'=Write, '1'=Read
        start    : in    std_logic;
        num_bytes: in    integer range 1 to 4;           -- Bytes de datos (modo write)
        -- Datos
        addr_dev : in    std_logic_vector(6 downto 0);
        addr_reg : in    std_logic_vector(7 downto 0);
        data_wr  : in    std_logic_vector(31 downto 0);  -- Datos a escribir (MSB first)
        data_rd  : out   std_logic_vector(7 downto 0);   -- Byte leído (modo read)
        -- Estado
        busy     : out   std_logic;
        done     : out   std_logic;
        error    : out   std_logic;
        -- Bus I2C
        sclk     : out   std_logic;
        sdata    : inout std_logic
    );
end I2C_CONTROLLER;

architecture Behavioral of I2C_CONTROLLER is

    -- -------------------------------------------------------------------------
    -- Tipo de estado
    -- -------------------------------------------------------------------------
    type state_t is (
        IDLE,
        -- Condición START / Repeated START
        START_SDA_LOW,
        START_SCL_LOW,
        -- Transmisión de un byte (escritura master?esclavo)
        TX_BIT_LOW,
        TX_BIT_HIGH,
        -- Espera ACK del esclavo
        ACK_SCL_LOW,
        ACK_SCL_HIGH,
        -- Recepción de un byte (lectura esclavo?master)
        RX_BIT_LOW,
        RX_BIT_HIGH,
        -- Envío ACK/NACK del master al esclavo
        MACK_SCL_LOW,
        MACK_SCL_HIGH,
        -- Condición STOP
        STOP_SCL_LOW,
        STOP_SDA_LOW,
        STOP_SCL_HIGH,
        -- Fin
        FINISHED,
        ERROR_STATE
    );

    signal state     : state_t := IDLE;

    -- -------------------------------------------------------------------------
    -- Clock divider
    -- -------------------------------------------------------------------------
    signal clk_cnt   : integer range 0 to CLK_DIV_G-1 := 0;
    signal tick      : std_logic := '0';   -- '1' un ciclo cada CLK_DIV_G ciclos

    -- -------------------------------------------------------------------------
    -- Registros internos
    -- -------------------------------------------------------------------------
    signal bit_cnt   : integer range 0 to 7 := 7;
    signal byte_cnt  : integer range 0 to 5 := 0;  -- 0=addr+W, 1=reg, 2..=datos, last=addr+R

    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_reg    : std_logic_vector(7 downto 0) := (others => '0');

    signal sclk_r    : std_logic := '1';
    signal sdata_out : std_logic := '1';
    signal sdata_oe  : std_logic := '0';  -- '1' = master conduce SDA

    -- Registros de los parámetros de la transacción (latched al inicio)
    signal rw_r      : std_logic := '0';
    signal nb_r      : integer range 1 to 4 := 1;
    signal addr_r    : std_logic_vector(6 downto 0) := (others => '0');
    signal areg_r    : std_logic_vector(7 downto 0) := (others => '0');
    signal dwr_r     : std_logic_vector(31 downto 0) := (others => '0');

    -- Flag para saber si el siguiente ACK es el último antes de parar
    signal last_data  : std_logic := '0';
    -- Flag para saber si estamos en la fase de lectura (tras repeated start)
    signal in_read    : std_logic := '0';

begin

    -- =========================================================================
    -- Buffer triestado SDA
    -- =========================================================================
    sdata <= sdata_out when sdata_oe = '1' else 'Z';
    sclk  <= sclk_r;

    -- =========================================================================
    -- Generador de tick (1 pulso cada CLK_DIV_G ciclos)
    -- =========================================================================
    p_clkdiv : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                clk_cnt <= 0;
                tick    <= '0';
            elsif clk_cnt = CLK_DIV_G - 1 then
                clk_cnt <= 0;
                tick    <= '1';
            else
                clk_cnt <= clk_cnt + 1;
                tick    <= '0';
            end if;
        end if;
    end process p_clkdiv;

    -- =========================================================================
    -- Máquina de estados - avanza sólo en cada tick
    -- =========================================================================
    p_fsm : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state     <= IDLE;
                sclk_r    <= '1';
                sdata_out <= '1';
                sdata_oe  <= '0';
                busy      <= '0';
                done      <= '0';
                error     <= '0';
                bit_cnt   <= 7;
                byte_cnt  <= 0;
                in_read   <= '0';
                last_data <= '0';
                data_rd   <= (others => '0');

            elsif tick = '1' then

                -- Defecto: pulsos de un ciclo
                done  <= '0';
                error <= '0';

                case state is

                    -- ---------------------------------------------------------
                    when IDLE =>
                        busy      <= '0';
                        sclk_r    <= '1';
                        sdata_out <= '1';
                        sdata_oe  <= '1';
                        in_read   <= '0';
                        if start = '1' then
                            -- Latch de parámetros
                            rw_r     <= rw;
                            nb_r     <= num_bytes;
                            addr_r   <= addr_dev;
                            areg_r   <= addr_reg;
                            dwr_r    <= data_wr;
                            busy     <= '1';
                            byte_cnt <= 0;
                            state    <= START_SDA_LOW;
                        end if;

                    -- ---------------------------------------------------------
                    -- Condición START: SDA baja con SCL alto
                    -- ---------------------------------------------------------
                    when START_SDA_LOW =>
                        sdata_out <= '0';   -- SDA baja ? START
                        state     <= START_SCL_LOW;

                    when START_SCL_LOW =>
                        sclk_r    <= '0';   -- SCL baja para empezar a transmitir
                        -- Cargamos primer byte: ADDR + R/W
                        -- Si in_read='1' estamos en repeated start ? ADDR+R
                        -- Si in_read='0' ? ADDR+W
                        if in_read = '1' then
                            shift_reg <= addr_r & '1';
                        else
                            shift_reg <= addr_r & '0';
                        end if;
                        bit_cnt   <= 7;
                        state     <= TX_BIT_LOW;

                    -- ---------------------------------------------------------
                    -- Transmisión de un byte (master ? esclavo)
                    -- ---------------------------------------------------------
                    when TX_BIT_LOW =>
                        sclk_r    <= '0';
                        sdata_oe  <= '1';
                        sdata_out <= shift_reg(bit_cnt);
                        state     <= TX_BIT_HIGH;

                    when TX_BIT_HIGH =>
                        sclk_r <= '1';
                        if bit_cnt = 0 then
                            state <= ACK_SCL_LOW;
                        else
                            bit_cnt <= bit_cnt - 1;
                            state   <= TX_BIT_LOW;
                        end if;

                    -- ---------------------------------------------------------
                    -- Espera ACK del esclavo
                    -- ---------------------------------------------------------
                    when ACK_SCL_LOW =>
                        sclk_r   <= '0';
                        sdata_oe <= '0';    -- Soltamos SDA para que esclavo ponga ACK
                        state    <= ACK_SCL_HIGH;

                    when ACK_SCL_HIGH =>
                        sclk_r <= '1';
                        if sdata = '1' then
                            -- NACK ? abortar
                            state <= ERROR_STATE;
                        else
                            -- ACK OK ? decidir siguiente acción según byte_cnt
                            if in_read = '1' then
                                -- Acabamos de enviar ADDR+R, empezamos a leer
                                bit_cnt <= 7;
                                rx_reg  <= (others => '0');
                                state   <= RX_BIT_LOW;
                            elsif byte_cnt = 0 then
                                -- Fin de ADDR+W ? enviar registro
                                shift_reg <= areg_r;
                                bit_cnt   <= 7;
                                byte_cnt  <= 1;
                                state     <= TX_BIT_LOW;
                            elsif byte_cnt = 1 then
                                -- Fin de REG
                                if rw_r = '1' then
                                    -- Repeated START para lectura
                                    in_read   <= '1';
                                    sdata_out <= '1';
                                    sdata_oe  <= '1';
                                    state     <= START_SDA_LOW;
                                else
                                    -- Escritura: enviar bytes de datos
                                    shift_reg <= dwr_r(31 downto 24);
                                    bit_cnt   <= 7;
                                    byte_cnt  <= 2;
                                    state     <= TX_BIT_LOW;
                                end if;
                            elsif byte_cnt <= nb_r then
                                -- Enviando bytes de datos (byte_cnt va de 2 a nb_r+1)
                                -- byte_cnt=2 ? dwr_r(23..16), 3?(15..8), 4?(7..0)
                                case byte_cnt is
                                    when 2      => shift_reg <= dwr_r(23 downto 16);
                                    when 3      => shift_reg <= dwr_r(15 downto 8);
                                    when others => shift_reg <= dwr_r(7  downto 0);
                                end case;
                                bit_cnt  <= 7;
                                byte_cnt <= byte_cnt + 1;
                                state    <= TX_BIT_LOW;
                            else
                                -- Todos los bytes enviados ? STOP
                                state <= STOP_SCL_LOW;
                            end if;
                        end if;

                    -- ---------------------------------------------------------
                    -- Recepción de un byte (esclavo ? master)
                    -- ---------------------------------------------------------
                    when RX_BIT_LOW =>
                        sclk_r   <= '0';
                        sdata_oe <= '0';    -- Master en alta impedancia
                        state    <= RX_BIT_HIGH;

                    when RX_BIT_HIGH =>
                        sclk_r              <= '1';
                        rx_reg(bit_cnt)     <= sdata;   -- Muestreamos SDA
                        if bit_cnt = 0 then
                            -- Byte completo recibido
                            data_rd <= rx_reg(7 downto 1) & sdata; -- incluimos último bit
                            -- Master envía NACK (último byte) ? indica fin de lectura
                            state <= MACK_SCL_LOW;
                        else
                            bit_cnt <= bit_cnt - 1;
                            state   <= RX_BIT_LOW;
                        end if;

                    -- ---------------------------------------------------------
                    -- Master envía NACK tras recibir el byte (fin de lectura)
                    -- ---------------------------------------------------------
                    when MACK_SCL_LOW =>
                        sclk_r    <= '0';
                        sdata_oe  <= '1';
                        sdata_out <= '1';   -- NACK = SDA en alto
                        state     <= MACK_SCL_HIGH;

                    when MACK_SCL_HIGH =>
                        sclk_r <= '1';
                        state  <= STOP_SCL_LOW;

                    -- ---------------------------------------------------------
                    -- Condición STOP: SDA sube con SCL alto
                    -- ---------------------------------------------------------
                    when STOP_SCL_LOW =>
                        sclk_r    <= '0';
                        sdata_oe  <= '1';
                        sdata_out <= '0';
                        state     <= STOP_SDA_LOW;

                    when STOP_SDA_LOW =>
                        sclk_r <= '1';      -- SCL sube primero
                        state  <= STOP_SCL_HIGH;

                    when STOP_SCL_HIGH =>
                        sdata_out <= '1';   -- SDA sube ? STOP
                        state     <= FINISHED;

                    -- ---------------------------------------------------------
                    when FINISHED =>
                        done  <= '1';
                        busy  <= '0';
                        state <= IDLE;

                    -- ---------------------------------------------------------
                    when ERROR_STATE =>
                        error     <= '1';
                        busy      <= '0';
                        sclk_r    <= '1';
                        sdata_out <= '1';
                        sdata_oe  <= '1';
                        -- Generamos STOP para liberar el bus antes de ir a IDLE
                        state     <= STOP_SCL_LOW;

                    when others =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

end Behavioral;