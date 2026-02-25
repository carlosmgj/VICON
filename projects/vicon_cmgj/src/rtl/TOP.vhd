--! \file DUT.vhd
--! Archivo fuente VHDL para el controlador a desarrollar.
--! \mainpage Proyecto VICON
--! \section title1 Descripcion
--! \image html diagram.svg "Diagrama logico"
--! El proyecto consiste en el desarrollo de un controlador del sensor de imagen MT9V111, incluyendo la comunicación i2c y la transimión de señales por FTDI.
--! \section source_code Código fuente
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

    -- 1. Señales para conectar con el Controlador I2C
    signal i2c_start     : std_logic := '0';
    signal i2c_num_bytes : integer range 1 to 4 := 3; -- Para el MT9V111: Reg + 2 Bytes data = 3
    signal i2c_reg_addr  : std_logic_vector(7 downto 0) := (others => '0');
    signal i2c_data_wr   : std_logic_vector(15 downto 0) := (others => '0');
    signal i2c_busy      : std_logic;
    signal i2c_done      : std_logic;

    -- 2. Nueva FSM simplificada del TOP (Gestor de alto nivel)
    -- Ya no necesitamos estados de bits, solo estados de transacciones
    type main_state_t is (IDLE, SETUP_SENSOR, WAIT_I2C, FINISH_ALL);
    signal current_state : main_state_t := IDLE;

begin

    -- 3. INSTANCIA DEL CONTROLADOR I2C
    -- Sustituye a toda la lógica de bits y clk_div que tenías antes
    u_i2c_core : entity work.I2C_CONTROLLER
        port map (
            clk          => clk,
            reset        => reset,
            start        => i2c_start,
            num_bytes    => i2c_num_bytes,
            addr_dev     => SENSOR_ADDR,
            addr_reg     => i2c_reg_addr,
            data_wr      => i2c_data_wr,
            busy         => i2c_busy,
            done         => i2c_done,
            sclk         => sclk,
            sdata        => sdata
        );

    -- 4. PROCESO DE CONTROL DEL TOP
    -- Este proceso solo decide QUÉ enviar, no CÓMO enviarlo bit a bit
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_state <= IDLE;
                i2c_start     <= '0';
                done          <= '0';
            else
                case current_state is
                    
                    when IDLE =>
                        done <= '0';
                        if reset = '0' then -- Ejemplo: Iniciar al salir de reset
                            current_state <= SETUP_SENSOR;
                        end if;

                    when SETUP_SENSOR =>
                        -- Ejemplo: Escribir en el registro 0x00 el valor 0x823A
                        if i2c_busy = '0' then
                            i2c_reg_addr  <= x"00";     -- Dirección del registro
                            i2c_data_wr   <= x"823A";   -- Dato de 16 bits
                            i2c_num_bytes <= 3;         -- 1 byte addr + 2 bytes data
                            i2c_start     <= '1';       -- Pulso de inicio
                            current_state <= WAIT_I2C;
                        end if;

                    when WAIT_I2C =>
                        i2c_start <= '0'; -- Bajamos el start para no repetir la orden
                        if i2c_done = '1' then
                            current_state <= FINISH_ALL;
                        end if;

                    when FINISH_ALL =>
                        done <= '1';
                        current_state <= FINISH_ALL; -- Fin de la secuencia

                    when others => 
                        current_state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;