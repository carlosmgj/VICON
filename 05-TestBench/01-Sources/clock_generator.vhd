--! \file clock_generator.vhd
--! \brief Generador de reloj y reset para simulación.


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library work;
use work.sim_utils_pkg.all;

entity clk_reset_gen is
    generic (
        g_RESET_DURATION : time := 100 ns  --! Duración del reset activo al inicio de la simulación
    );
    port (
        clk_out   : out std_logic;  --! Reloj 100 MHz generado
        reset_out : out std_logic   --! Reset activo alto; se desactiva tras g_RESET_DURATION
    );
end entity clk_reset_gen;

architecture sim of clk_reset_gen is

    signal s_clk   : std_logic := '0';  --! Registro interno del reloj
    signal s_reset : std_logic := '1';  --! Registro interno del reset (arranca activo)

begin

    clk_out   <= s_clk;
    reset_out <= s_reset;

    --! \brief Generador de reloj — periodo definido por c_CLK_PERIOD de sim_utils_pkg
    p_clk : process
    begin
        loop
            s_clk <= '0';
            wait for c_CLK_PERIOD / 2;
            s_clk <= '1';
            wait for c_CLK_PERIOD / 2;
        end loop;
    end process p_clk;

    --! \brief Generador de reset — activo alto durante g_RESET_DURATION
    p_reset : process
    begin
        s_reset <= '1';
        wait for g_RESET_DURATION;
        s_reset <= '0';
        wait;
    end process p_reset;

end architecture sim;
