--! \file ftdi_agent.vhd
--! \brief Agente de simulación del chip FT232H en modo Synchronous FIFO.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

library work;
use work.config_pkg.all;
use work.sim_utils_pkg.all;

entity ftdi_agent is
    generic (
        g_LOG_FILE    : string  := "ftdi_rx_log.txt";  --! Fichero de salida para bytes recibidos
        g_TXE_READY   : std_logic := '0'               --! Valor inicial de TXE# ('0'=listo, '1'=ocupado)
    );
    port (
        acbus_io : inout std_logic_vector(c_FTDI_CONTROLBUS_W-1 downto 0);  --! Bus de control FTDI (comparte con TOP)
        adbus_i  : in    std_logic_vector(c_FTDI_DATABUS_W-1    downto 0)   --! Bus de datos FTDI (TOP → agente)
    );
end entity ftdi_agent;

architecture sim of ftdi_agent is

    constant c_FTDI_CLK_PERIOD : time := 1 sec / 60_000_000;  --! Periodo del reloj FTDI (≈16.67 ns)

    signal s_clkout : std_logic := '0';  --! CLKOUT 60 MHz generado internamente
    signal s_txe_n  : std_logic := '1';  --! TXE# conducido por el agente
    signal s_rxf_n  : std_logic := '1';  --! RXF# conducido por el agente (no usado en escritura)

begin

    ---------------------------------------------------------------------------
    -- Conducir bits propios del agente en el ACBUS; soltar el resto ('Z')
    ---------------------------------------------------------------------------
    acbus_io                        <= (others => 'Z');
    acbus_io(c_FTDI_ACBUS_CLKOUT)  <= s_clkout;
    acbus_io(c_FTDI_ACBUS_TXE_N)   <= s_txe_n;
    acbus_io(c_FTDI_ACBUS_RXF_N)   <= s_rxf_n;

    ---------------------------------------------------------------------------
    --! \brief Generador de CLKOUT 60 MHz
    ---------------------------------------------------------------------------
    p_clkout : process
    begin
        loop
            s_clkout <= '0';
            wait for c_FTDI_CLK_PERIOD / 2;
            s_clkout <= '1';
            wait for c_FTDI_CLK_PERIOD / 2;
        end loop;
    end process p_clkout;

    ---------------------------------------------------------------------------
    --! \brief Control de TXE# y recepción de datos
    --!
    --! Mantiene TXE# al valor de g_TXE_READY.
    --! En cada flanco de subida de WR# (fin del pulso de escritura) captura
    --! el byte presente en ADBUS y lo vuelca al fichero de log.
    ---------------------------------------------------------------------------
    p_rx : process
        variable v_byte_cnt : integer := 0;
        variable v_line     : line;
        file     f_log      : text;
    begin
        s_txe_n <= g_TXE_READY;

        file_open(f_log, g_LOG_FILE, write_mode);
        write(v_line, string'("[FTDI AGENT] Inicio de captura"));
        writeline(f_log, v_line);

        loop
            -- WR# sube → TOP ha terminado el pulso de escritura; dato estable en ADBUS
            wait until rising_edge(acbus_io(c_FTDI_ACBUS_WR_N));
            v_byte_cnt := v_byte_cnt + 1;
            write(v_line,
                "[" & time'image(now) & "]" &
                " Byte #" & integer'image(v_byte_cnt) &
                " : 0x"   & int_to_hex_str(to_integer(unsigned(adbus_i)), 2));
            writeline(f_log, v_line);
        end loop;

        file_close(f_log);
        wait;
    end process p_rx;

end architecture sim;
