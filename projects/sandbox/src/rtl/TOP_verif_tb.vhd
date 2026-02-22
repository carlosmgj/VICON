--! \file TOP_verif_tb.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;


entity TOP_verif_tb is
end TOP_verif_tb;

architecture Behavioral of TOP_verif_tb is
    -- Señales de conexión
    signal clk     : std_logic := '0';
    signal sw      : std_logic_vector(15 downto 0) := (others => '0');
    signal cat     : std_logic_vector(7 downto 0);
    signal an      : std_logic_vector(3 downto 0); 
    signal btn     : std_logic_vector(4 downto 0) := (others => '0');
    
    signal test_marker: integer := 0;
    
    -- Reloj de 100MHz (10 ns de periodo) 
    constant CLK_PERIOD : time := 10 ns;

    -- FUNCIÓN DE AYUDA (VHDL-93): Convierte std_logic_vector a String para los reportes
    function vec_to_str(vec : std_logic_vector) return string is
        variable res : string(1 to vec'length);
    begin
        for i in 0 to vec'length-1 loop
            if vec(vec'high-i) = '1' then 
                res(i+1) := '1';
            elsif vec(vec'high-i) = '0' then 
                res(i+1) := '0';
            else 
                res(i+1) := 'X';
            end if;
        end loop;
        return res;
    end function;

    -- Procedimiento corregido con IF-ELSE y sincronización de ánodo
    procedure check_hex_value(
    constant input_val   : in std_logic_vector(3 downto 0);
    constant expected_cat : in std_logic_vector(7 downto 0);
    signal sw_signal     : out std_logic_vector(15 downto 0);
    signal cat_signal    : in std_logic_vector(7 downto 0);
    signal an_signal     : in std_logic_vector(3 downto 0);
    signal marker        : inout integer
) is
    file f : text;
    variable l : line;
begin
    sw_signal(3 downto 0) <= input_val;
    marker <= marker + 10;
    
    wait until an_signal = "1110" for 1 ms;
    wait for 5 ns;
    marker <= marker + 1;

    -- Abrimos el archivo en modo "append" para no borrar lo anterior
    file_open(f, "reporte_final_1.txt", append_mode);

    if (cat_signal = expected_cat) then
        -- Formato para OK
        write(l, "[" & time'image(now) & "] - INFO : SW->" & vec_to_str(input_val) &": OK | Esperado: " & vec_to_str(expected_cat) & " Actual: " & vec_to_str(cat_signal));
        report "[SIM] OK";
    else
        -- Formato para FALLO
        write(l, "[" & time'image(now) & "] - ERROR : FALLO | Esperado: " & vec_to_str(expected_cat) & " Actual: " & vec_to_str(cat_signal));
        report "[SIM] FAIL" severity error;
    end if;

    writeline(f, l);
    file_close(f); -- Cerramos inmediatamente para liberar el archivo
end procedure;

begin
    -- Instancia del DUT (Device Under Test) [cite: 112]
    dut: entity work.TOP
        generic map ( N => 4 ) -- N pequeño para que el multiplexor rote rápido en simulación [cite: 87, 95]
        port map (
            MCLK => clk, 
            SW   => sw, 
            BTN  => btn, 
            LED  => open, 
            CAT  => cat, 
            AN   => an 
        );

    -- Generador de reloj [cite: 114]
    clk <= not clk after CLK_PERIOD/2;

    -- Proceso principal de verificación
    stim_proc: process
        file f_reset : text;
    begin
        file_open(f_reset, "reporte_final_1.txt", write_mode);
        file_close(f_reset);
        -- Inicialización y Reset (BTN0 es el reset en este diseño)
        btn(0) <= '1';
        wait for 100 ns;
        btn(0) <= '0';
        wait for 20 ns;
        
        report "--- [" & time'image(now) & "] INICIANDO TEST DE DECODIFICADOR ---"; 
        
        -- Prueba valor "0"
        test_marker <= 0;
        check_hex_value(X"0", "11000000", sw, cat, an, test_marker);
        
        -- Prueba valor "1"
        test_marker <= 1;
        check_hex_value(X"1", "11111001", sw, cat, an, test_marker);
        
        -- Prueba valor "A"
        test_marker <= 2;
        check_hex_value(X"A", "10001000", sw, cat, an, test_marker);
        
        report "--- [" & time'image(now) & "] TEST FINALIZADO ---"; 
        test_marker <= 100;
        wait;
    end process;

end Behavioral;