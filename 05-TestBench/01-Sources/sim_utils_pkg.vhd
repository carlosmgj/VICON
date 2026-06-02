--! \file sim_utils_pkg.vhd
--! \brief Paquete de utilidades para simulación VHDL.
--!
--! Proporciona:
--!   - Constantes globales de simulación
--!   - Constantes reducidas para acelerar la simulación
--!   - Funciones de conversión de tipos para logging
--!   - Procedimiento de log a fichero con timestamp
--!   - Procedimiento de verificación con scoreboard y reporte a fichero

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

package sim_utils_pkg is

    ---------------------------------------------------------------------------
    -- Constantes globales de simulación
    ---------------------------------------------------------------------------
    constant c_CLK_PERIOD       : time    := 10 ns;  --! Periodo del reloj de sistema en simulación (100 MHz)
    constant c_TXE_READY_CYCLES : integer := 200;
    constant c_TXE_BUSY_CYCLES  : integer := 800;

    ---------------------------------------------------------------------------
    -- Funciones de conversión para logging
    ---------------------------------------------------------------------------

    --! \brief Convierte un std_logic_vector a string de '0'/'1'/'X'
    function vec_to_str(vec : std_logic_vector) return string;

    --! \brief Convierte un integer a string hexadecimal de anchura fija
    --! \param val   Valor a convertir
    --! \param width Número de dígitos hex del resultado (default: 2)
    function int_to_hex_str(val : integer; width : integer := 2) return string;

    ---------------------------------------------------------------------------
    -- Procedimientos de simulación
    ---------------------------------------------------------------------------

    --! \brief Escribe una línea en un fichero de log con timestamp y prefijo INFO/ERROR
    --! \param file_name Nombre del fichero de salida
    --! \param message   Mensaje a escribir
    --! \param is_error  Si true, prefijo "ERROR:"; si false, prefijo "INFO :"
    procedure log_to_file(
        constant file_name : in string;
        constant message   : in string;
        constant is_error  : in boolean := false
    );

    --! \brief Compara actual con expected; registra resultado en scoreboard y fichero
    --! \param actual    Valor obtenido de la simulación
    --! \param expected  Valor esperado
    --! \param msg_tag   Etiqueta identificativa del punto de verificación
    --! \param error_cnt Contador de errores acumulados (inout)
    --! \param file_name Fichero de reporte (default: "reporte_final_1.txt")
    procedure check_value(
        constant actual    : in    std_logic_vector;
        constant expected  : in    std_logic_vector;
        constant msg_tag   : in    string;
        variable error_cnt : inout integer;
        constant file_name : in    string := "reporte_final_1.txt"
    );

end package sim_utils_pkg;

package body sim_utils_pkg is

    ---------------------------------------------------------------------------
    function vec_to_str(vec : std_logic_vector) return string is
        variable v_res : string(1 to vec'length);
    begin
        for i in 0 to vec'length - 1 loop
            if    vec(vec'high - i) = '1' then v_res(i + 1) := '1';
            elsif vec(vec'high - i) = '0' then v_res(i + 1) := '0';
            else                               v_res(i + 1) := 'X';
            end if;
        end loop;
        return v_res;
    end function vec_to_str;

    ---------------------------------------------------------------------------
    function int_to_hex_str(val : integer; width : integer := 2) return string is
        constant c_HEX_CHARS : string(1 to 16)                  := "0123456789ABCDEF";
        variable v_temp      : std_logic_vector(width * 4 - 1 downto 0);
        variable v_res       : string(1 to width);
        variable v_nibble    : integer;
    begin
        v_temp := std_logic_vector(to_unsigned(val, width * 4));
        for i in 0 to width - 1 loop
            v_nibble         := to_integer(unsigned(v_temp((i + 1) * 4 - 1 downto i * 4)));
            v_res(width - i) := c_HEX_CHARS(v_nibble + 1);
        end loop;
        return v_res;
    end function int_to_hex_str;

    ---------------------------------------------------------------------------
    procedure log_to_file(
        constant file_name : in string;
        constant message   : in string;
        constant is_error  : in boolean := false
    ) is
        file     f_out   : text;
        variable v_line  : line;
        variable v_prefix : string(1 to 7);
    begin
        if is_error then
            v_prefix := "ERROR :";
        else
            v_prefix := "INFO  :";
        end if;
        file_open(f_out, file_name, append_mode);
        write(v_line, "[" & time'image(now) & "] - " & v_prefix & " " & message);
        writeline(f_out, v_line);
        file_close(f_out);
    end procedure log_to_file;

    ---------------------------------------------------------------------------
    procedure check_value(
        constant actual    : in    std_logic_vector;
        constant expected  : in    std_logic_vector;
        constant msg_tag   : in    string;
        variable error_cnt : inout integer;
        constant file_name : in    string := "reporte_final_1.txt"
    ) is
    begin
        if actual = expected then
            log_to_file(file_name, msg_tag & " OK    | Val: " & vec_to_str(actual), false);
            report "[SIM] " & msg_tag & " OK";
        else
            error_cnt := error_cnt + 1;
            log_to_file(file_name,
                msg_tag & " FALLO | Exp: " & vec_to_str(expected) &
                          "  Act: " & vec_to_str(actual), true);
            report "[SIM] " & msg_tag & " FAIL" severity error;
        end if;
    end procedure check_value;

end package body sim_utils_pkg;
