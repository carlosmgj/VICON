library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

package sim_utils_pkg is

    -- Constantes globales de simulación
    constant CLK_PERIOD : time := 10 ns;

    -- Función para convertir vectores a texto (mejorada)
    function vec_to_str(vec : std_logic_vector) return string;

    -- Procedimiento universal de logeo en archivo
    procedure log_to_file(
        constant file_name : in string;
        constant message   : in string;
        constant is_error  : in boolean := false
    );

    -- Procedimiento de verificación con "Scoreboard" (marcador)
    procedure check_value(
        constant actual    : in std_logic_vector;
        constant expected  : in std_logic_vector;
        constant msg_tag   : in string;
        variable error_cnt : inout integer;
        constant file_name : in string := "reporte_final_1.txt"
    );

end package;

package body sim_utils_pkg is

    function vec_to_str(vec : std_logic_vector) return string is
        variable res : string(1 to vec'length);
    begin
        for i in 0 to vec'length-1 loop
            if vec(vec'high-i) = '1' then res(i+1) := '1';
            elsif vec(vec'high-i) = '0' then res(i+1) := '0';
            else res(i+1) := 'X';
            end if;
        end loop;
        return res;
    end function;

    procedure log_to_file(
        constant file_name : in string;
        constant message   : in string;
        constant is_error  : in boolean := false
    ) is
        file f : text;
        variable l : line;
        variable prefix : string(1 to 7);
    begin
        if is_error then prefix := "ERROR :"; else prefix := "INFO  :"; end if;
        
        file_open(f, file_name, append_mode);
        write(l, "[" & time'image(now) & "] - " & prefix & " " & message);
        writeline(f, l);
        file_close(f);
    end procedure;

    procedure check_value(
        constant actual    : in std_logic_vector;
        constant expected  : in std_logic_vector;
        constant msg_tag   : in string;
        variable error_cnt : inout integer;
        constant file_name : in string := "reporte_final_1.txt"
    ) is
    begin
        if (actual = expected) then
            log_to_file(file_name, msg_tag & " OK | Val: " & vec_to_str(actual), false);
            report "[SIM] " & msg_tag & " OK";
        else
            error_cnt := error_cnt + 1;
            log_to_file(file_name, msg_tag & " FALLO | Exp: " & vec_to_str(expected) & " Act: " & vec_to_str(actual), true);
            report "[SIM] " & msg_tag & " FAIL" severity error;
        end if;
    end procedure;

end package body;