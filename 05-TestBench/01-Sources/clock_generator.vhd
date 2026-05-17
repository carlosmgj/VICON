library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity clk_reset_gen is
    port (
        clk_out   : out std_logic;
        reset_out : out std_logic
    );
end clk_reset_gen;

architecture Behavioral of clk_reset_gen is
    signal clk_i   : std_logic := '0';
    signal reset_i : std_logic := '1'; -- Empezamos en reset
begin

    -- Generador de Reloj (100 MHz -> Periodo 10ns)
    -- Nota: Esto solo funcionará en SIMULACIÓN. 
    process
    begin
        clk_i <= '0';
        wait for 5 ns;
        clk_i <= '1';
        wait for 5 ns;
    end process;

    -- Generador de Reset
    process
    begin
        reset_i <= '1';    -- Activo
        wait for 100 ns;   -- Duración del reset
        reset_i <= '0';    -- Desactivado para siempre
        wait;              -- Detener proceso
    end process;

    -- Salidas
    clk_out   <= clk_i;
    reset_out <= reset_i;

end Behavioral;