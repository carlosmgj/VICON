--! \file DUT.vhd
--! Archivo fuente VHDL para el controlador a desarrollar.
--! \mainpage Proyecto VICON
--! \section title1 Descripcion
--! \image html diagram.svg "Diagrama logico"
--! El proyecto consiste en el desarrollo de un controlador del sensor de imagen MT9V111, incluyendo la comunicaci√≥n i2c y la transimi√≥n de se√±ales por FTDI.
--! \section source_code C√≥digo fuente
--! - <A HREF=_d_u_t_8vhd_source.html><B> DUT.vhd</B></A>
--! \note El formato de comentario incluye ! para poder realizar documentacion dinamica con Doxygen. 
--! \section Verificacion
--! \subsection DUT
--! \subsection agent_mt9v111 Agente MT9V111
--! \subsection agent_ftdi Agente FTDDI
--! \section author Author
--! Carlos Manuel Gomez Jimenez, DNI: 76037985P
--! \page Informe_E/S 
--! \include io_report.txt
--! \page Informe_Utilizacion
--! \include synthesis_utilization.txt
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TOP is
    generic (
        SENSOR_ADDR : std_logic_vector(6 downto 0) := "1011100" -- 0x5C
    );
    port (
        clk      : in    std_logic;
        reset    : in    std_logic;
        sclk     : out   std_logic;
        sdata    : inout std_logic;
        done     : out   std_logic
    );
end TOP;

architecture Behavioral of TOP is
    -- FSM Estados: Incluimos sub-pasos para manejar el flanco de SCLK
    type state_t is (IDLE, START, SEND_ADDR_LOW, SEND_ADDR_HIGH, ACK_WAIT, ACK_CHECK, STOP, FINISHED);
    signal state      : state_t := IDLE;
    
    signal bit_cnt    : integer range 0 to 7 := 7;
    signal clk_div    : unsigned(15 downto 0) := (others => '0');
    signal en_i2c     : std_logic := '0';
    
    -- SeÔøΩales internas para el buffer triestado
    signal sdata_out  : std_logic := '1';
    signal sdata_oe   : std_logic := '0'; -- '1' para escribir, '0' para leer (Z)

begin

    -- 1. Generador de Enable (100kHz). 100MHz / 1000 = 100kHz.
    -- Usamos un pulso de un solo ciclo de clk para no anidar flancos.
    process(clk)
    begin
        if rising_edge(clk) then
            if clk_div = 1000 then 
                clk_div <= (others => '0');
                en_i2c  <= '1';
            else
                clk_div <= clk_div + 1;
                en_i2c  <= '0';
            end if;
        end if;
    end process;

    -- 2. LÔøΩgica del Buffer Triestado para SDATA
    sdata <= sdata_out when sdata_oe = '1' else 'Z';

    -- 3. MÔøΩquina de Estados Principal
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
            elsif en_i2c = '1' then
                case state is
                    
                    when IDLE =>
                        sclk      <= '1';
                        sdata_out <= '1';
                        sdata_oe  <= '1';
                        state     <= START;

                    when START =>
                        sdata_out <= '0'; -- SDA cae mientras SCL es 1
                        state     <= SEND_ADDR_LOW;
                        bit_cnt   <= 7;

                    when SEND_ADDR_LOW =>
                        sclk <= '0';
                        if bit_cnt > 0 then
                            sdata_out <= SENSOR_ADDR(bit_cnt - 1); -- EnvÌa los 7 bits de la direcciÛn
                        else
                            sdata_out <= '0'; -- El bit 0 es el R/W (0 para Write)
                        end if;
                        state <= SEND_ADDR_HIGH;

                    when SEND_ADDR_HIGH =>
                        sclk      <= '1'; -- Subimos reloj para que el esclavo lea
                        if bit_cnt = 0 then
                            state <= ACK_WAIT;
                        else
                            bit_cnt <= bit_cnt - 1;
                            state   <= SEND_ADDR_LOW;
                        end if;
                        
                    when ACK_WAIT =>
                        sclk <= '0';      -- Bajamos el reloj tras el 8∫ bit
                        sdata_oe <= '0';  -- LIBERAMOS EL BUS (Z). Ahora el esclavo puede poner el ACK.
                        state <= ACK_CHECK;

                    when ACK_CHECK =>
                        sclk     <= '1';
                        sdata_oe <= '0'; -- LIBERAMOS EL BUS (Z) para recibir ACK
                        state    <= STOP;

                    when STOP =>
                        sclk      <= '0';
                        sdata_oe  <= '1';
                        sdata_out <= '0';
                        -- En el siguiente tick, SCL sube y luego SDA sube
                        state     <= FINISHED;

                    when FINISHED =>
                        sclk      <= '1';
                        sdata_out <= '1'; -- STOP: SDA sube mientras SCL es 1
                        done      <= '1';
                        state     <= FINISHED;

                    when others => state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;