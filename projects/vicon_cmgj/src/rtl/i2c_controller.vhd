--! \file i2c_controller.vhd
--! Controlador I2C para el sensor MT9V111. Implementa una escritura simple a la dirección del sensor.


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity I2C_CONTROLLER is
    port (
        clk      : in    std_logic;
        reset    : in    std_logic;
        start    : in    std_logic;
        num_bytes: in    integer range 1 to 4;
        addr_dev : in    std_logic_vector(6 downto 0);
        addr_reg : in    std_logic_vector(7 downto 0);
        data_wr  : in    std_logic_vector(15 downto 0);
        busy     : out   std_logic := '0';
        sclk     : out   std_logic;
        sdata    : inout std_logic;
        done     : out   std_logic
    );
end I2C_CONTROLLER;

architecture Behavioral of I2C_CONTROLLER is
    type state_t is (
            IDLE, 
            START_COND,
            BIT_LOW,
            BIT_HIGH,
            ACK_WAIT_LOW,
            ACK_WAIT_HIGH,
            STOP_LOW,
            STOP_HIGH,
            FINISHED);

    signal state      : state_t := IDLE;
    signal bit_cnt    : integer range 0 to 7 := 7;
    signal byte_cnt   : integer range 0 to 4 := 0;
    signal clk_div    : unsigned(15 downto 0) := (others => '0');
    signal shift_reg  : std_logic_vector(7 downto 0);
    signal en_i2c     : std_logic := '1';
    signal sdata_out  : std_logic := '1';
    signal sdata_oe   : std_logic := '0'; -- '1' para escribir, '0' para leer (Z)

begin


    -- 2. L�gica del Buffer Triestado para SDATA
    sdata <= sdata_out when sdata_oe = '1' else 'Z';

    -- 3. M�quina de Estados Principal
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state     <= IDLE;
                sclk      <= '1';
                sdata_out <= '1';
                sdata_oe  <= '0';
                done      <= '0';
                bit_cnt   <= 7;
                bit_cnt   <= 0;
            elsif en_i2c = '1' then
                case state is
                    
                    when IDLE =>
                        busy <= '0';
                        done <= '0';
                        sclk <= '1';
                        sdata_out <= '1';
                        sdata_oe  <= '1';
                        if start = '1' then
                            busy <= '1';
                            byte_cnt <= 0;
                            -- Preparamos el primer byte: Dirección + Escritura ('0')
                            shift_reg <= addr_dev & '0'; 
                            state <= START_COND;
                        end if;

                    when START_COND =>
                        sdata_out <= '0'; -- START: SDA cae con SCL alto
                        state <= BIT_LOW;
                        bit_cnt <= 7;

                    when BIT_LOW =>
                        sclk <= '0';
                        sdata_oe <= '1';
                        sdata_out <= shift_reg(bit_cnt); -- Ponemos el bit actual
                        state <= BIT_HIGH;

                    when BIT_HIGH =>
                        sclk <= '1'; -- Subimos reloj para que el esclavo lea
                        if bit_cnt = 0 then
                            state <= ACK_WAIT_LOW;
                        else
                            bit_cnt <= bit_cnt - 1;
                            state <= BIT_LOW;
                        end if;

                    when ACK_WAIT_LOW =>
                        sclk <= '0';
                        sdata_oe <= '0'; 
                        state <= ACK_WAIT_HIGH;

                    when ACK_WAIT_HIGH =>
                        sclk <= '1'; 
                        if sdata = '0' then

                            if byte_cnt = 0 then
                                shift_reg <= addr_reg;
                                byte_cnt  <= 1;
                                bit_cnt   <= 7;
                                state     <= BIT_LOW;
                                
                            elsif byte_cnt <= num_bytes then
                                if byte_cnt = 1 then
                                    shift_reg <= data_wr(15 downto 8); -- MSB
                                else
                                    shift_reg <= data_wr(7 downto 0);  -- LSB
                                end if;
                                
                                byte_cnt <= byte_cnt + 1;
                                bit_cnt  <= 7;
                                state    <= BIT_LOW;
                            else
                                state <= STOP_LOW;
                            end if;
                            
                        else
                            state <= STOP_LOW;

                        end if;

                    when STOP_LOW =>
                        sclk <= '0';
                        sdata_oe <= '1';
                        sdata_out <= '0';
                        state <= STOP_HIGH;

                    when STOP_HIGH =>
                        sclk <= '1'; -- SCL alto primero
                        state <= FINISHED;

                    when FINISHED =>
                        sdata_out <= '1'; -- SDA sube con SCL alto (STOP)
                        done <= '1';
                        state <= IDLE;

                    when others => state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;