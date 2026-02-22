library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

-- Importamos tu package de utilidades
use work.sim_utils_pkg.all; 

entity TOP_verif_tb is
end TOP_verif_tb;

architecture Behavioral of TOP_verif_tb is
    -- Se�ales de conexi�n
    signal clk     : std_logic := '0';
    signal sw      : std_logic_vector(15 downto 0) := (others => '0');
    signal cat     : std_logic_vector(7 downto 0);
    signal an      : std_logic_vector(3 downto 0);
    signal btn     : std_logic_vector(4 downto 0) := (others => '0');
    
begin
    -- Instancia del DUT (Device Under Test)
    dut: entity work.TOP
        generic map ( N => 4 ) 
        port map (
            MCLK => clk, 
            SW   => sw, 
            BTN  => btn, 
            LED  => open, 
            CAT  => cat, 
            AN   => an 
        );

    -- Generador de reloj usando la constante del package
    clk <= not clk after CLK_PERIOD/2;

    -- Proceso principal de verificaci�n
    stim_proc: process
        variable error_count : integer := 0; 
        file f_reset : text;
    begin
        file_open(f_reset, "reporte_final_1.txt", write_mode);
        file_close(f_reset);
        
        -- Inicializaci�n del archivo de reporte
        log_to_file("reporte_final_1.txt", "--- INICIANDO TEST DE DECODIFICADOR ---");

        -- Reset (BTN0)
        btn(0) <= '1';
        wait for 100 ns;
        btn(0) <= '0';
        wait for 50 ns;

        -- Prueba valor "0"
        sw(3 downto 0) <= X"0";
        wait until an = "1110" for 1 ms;
        wait for 20 ns;
        check_value(cat, "11000000", "VALOR_0", error_count);
        wait for 100 ns;

        -- Prueba valor "1"
        sw(3 downto 0) <= X"1";
        wait until an = "1110" for 1 ms;
        wait for 20 ns;
        -- log_to_file("reporte_final_1.txt", "[" & time'image(now) & "] - ENCONTRADO ENCENDIDO DEL DIGITO");
        check_value(cat, "11111001", "VALOR_1", error_count); -- Valor est�ndar para '1'
        wait for 100 ns;

        -- Prueba valor "A"
        sw(3 downto 0) <= X"A";
        wait until an = "1110" for 1 ms;
        wait for 20 ns;
        check_value(cat, "10001000", "VALOR_A", error_count); -- Valor est�ndar para 'A'
        wait for 100 ns;

        -- Reporte final
        log_to_file("reporte_final_1.txt", "--- TEST FINALIZADO. Errores: " & integer'image(error_count));
        
        report "Simulacion terminada con " & integer'image(error_count) & " errores.";
        wait;
    end process;

end Behavioral;