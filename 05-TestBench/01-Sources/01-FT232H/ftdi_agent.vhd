--! \file ftdi_agent.vhd
--! \brief Agente de simulacion del chip FT232H en modo Synchronous FIFO 245 con host PC asincrono.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

library work;
use work.config_pkg.all;
use work.sim_utils_pkg.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

entity ftdi_agent is
    generic (
        g_LOG_FILE                : string  := "ftdi_rx_log.txt";
        g_TX_FIFO_DEPTH           : integer := 512;
        g_TXE_BUSY_THRESHOLD      : integer := 480;
        g_TXE_BUSY_CYCLES         : integer := 1;
        g_PC_READ_START_THRESHOLD : integer := 100;
        g_PC_READ_PERIOD          : time    := 100 ns;
        g_PC_TO_FPGA_DEPTH        : integer := 0;
        g_PC_TO_FPGA_LOOP         : boolean := false
    );
    port (
        acbus_io : inout std_logic_vector(c_FTDI_CONTROLBUS_W-1 downto 0);
        adbus_io : inout std_logic_vector(c_FTDI_DATABUS_W-1    downto 0)
    );
end entity ftdi_agent;

architecture sim of ftdi_agent is

    constant c_FTDI_CLK_PERIOD : time := 1 sec / 60_000_000;

    constant c_FRAME_MARKER_0 : std_logic_vector(7 downto 0) := x"AA";
    constant c_FRAME_MARKER_1 : std_logic_vector(7 downto 0) := x"55";
    constant c_FRAME_MARKER_2 : std_logic_vector(7 downto 0) := x"AA";
    constant c_FRAME_MARKER_3 : std_logic_vector(7 downto 0) := x"55";

    type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    signal s_rx_fifo      : t_byte_array(0 to g_TX_FIFO_DEPTH-1) := (others => (others => '0'));
    signal s_rx_fifo_wr   : integer range 0 to g_TX_FIFO_DEPTH-1 := 0;
    signal s_rx_fifo_rd   : integer range 0 to g_TX_FIFO_DEPTH-1 := 0;
    signal s_rx_fifo_level: integer range 0 to g_TX_FIFO_DEPTH   := 0;
    signal s_rx_fifo_push : std_logic := '0';
    signal s_rx_fifo_din  : std_logic_vector(7 downto 0) := (others => '0');
    signal s_rx_fifo_pop  : std_logic := '0';
    signal s_rx_fifo_dout : std_logic_vector(7 downto 0) := (others => '0');
    signal s_rx_fifo_empty: std_logic := '1';
    signal s_rx_fifo_full : std_logic := '0';

    signal s_tx_fifo_level : integer range 0 to 65535 := 0;
    signal s_tx_fifo_dout  : std_logic_vector(7 downto 0) := (others => '0');

    signal s_clkout : std_logic := '0';
    signal s_txe_n  : std_logic := '0';
    signal s_rxf_n  : std_logic := '1';

begin

    acbus_io                      <= (others => 'Z');
    acbus_io(c_FTDI_ACBUS_CLKOUT) <= s_clkout;
    acbus_io(c_FTDI_ACBUS_TXE_N)  <= s_txe_n;
    acbus_io(c_FTDI_ACBUS_RXF_N)  <= s_rxf_n;

    adbus_io <= s_tx_fifo_dout
                when (To_X01(acbus_io(c_FTDI_ACBUS_OE_N))  = '0' and
                      To_X01(acbus_io(c_FTDI_ACBUS_RXF_N)) = '0')
                else (others => 'Z');

    s_rx_fifo_empty <= '1' when s_rx_fifo_level = 0               else '0';
    s_rx_fifo_full  <= '1' when s_rx_fifo_level = g_TX_FIFO_DEPTH else '0';
    s_rx_fifo_dout  <= s_rx_fifo(s_rx_fifo_rd);

    p_rx_fifo_ctrl : process
    begin
        loop
            wait until rising_edge(s_clkout);
            if s_rx_fifo_push = '1' and s_rx_fifo_full = '0' then
                s_rx_fifo(s_rx_fifo_wr) <= s_rx_fifo_din;
                if s_rx_fifo_wr = g_TX_FIFO_DEPTH-1 then
                    s_rx_fifo_wr <= 0;
                else
                    s_rx_fifo_wr <= s_rx_fifo_wr + 1;
                end if;
                s_rx_fifo_level <= s_rx_fifo_level + 1;
            end if;
            if s_rx_fifo_pop = '1' and s_rx_fifo_empty = '0' then
                if s_rx_fifo_rd = g_TX_FIFO_DEPTH-1 then
                    s_rx_fifo_rd <= 0;
                else
                    s_rx_fifo_rd <= s_rx_fifo_rd + 1;
                end if;
                if s_rx_fifo_push = '1' and s_rx_fifo_full = '0' then
                    null;
                else
                    s_rx_fifo_level <= s_rx_fifo_level - 1;
                end if;
            end if;
        end loop;
    end process p_rx_fifo_ctrl;

    p_clkout : process
    begin
        loop
            s_clkout <= '0'; wait for c_FTDI_CLK_PERIOD / 2;
            s_clkout <= '1'; wait for c_FTDI_CLK_PERIOD / 2;
        end loop;
    end process p_clkout;

    p_txe : process
    begin
        s_txe_n <= '0';
        if g_TXE_BUSY_CYCLES = 0 then
            log(ID_SEQUENCER, "TXE# fijo a '0' - proteccion desactivada", "FTDI_TXE");
            wait;
        end if;
        loop
            wait until s_rx_fifo_level >= g_TXE_BUSY_THRESHOLD;
            s_txe_n <= '1';
            log(ID_SEQUENCER, "TXE# -> '1' (buffer lleno, nivel=" &
                to_string(s_rx_fifo_level) & ")", "FTDI_TXE");
            for i in 1 to g_TXE_BUSY_CYCLES loop
                wait until rising_edge(s_clkout);
            end loop;
            wait until s_rx_fifo_level < (g_TXE_BUSY_THRESHOLD - 32);
            s_txe_n <= '0';
            log(ID_SEQUENCER, "TXE# -> '0' (buffer liberado)", "FTDI_TXE");
        end loop;
    end process p_txe;

    p_rx : process
        variable v_wrn_prev : std_logic := '1';
    begin
        s_rx_fifo_push <= '0';
        s_rx_fifo_din  <= (others => '0');
        loop
            wait until rising_edge(s_clkout);
            s_rx_fifo_push <= '0';
            if To_X01(acbus_io(c_FTDI_ACBUS_WR_N)) = '0' and
               v_wrn_prev = '0' and
               To_X01(s_txe_n) = '0' then
                s_rx_fifo_din  <= adbus_io;
                s_rx_fifo_push <= '1';
            end if;
            v_wrn_prev := To_X01(acbus_io(c_FTDI_ACBUS_WR_N));
        end loop;
    end process p_rx;

    p_pc_host_driver : process
        variable v_byte_cnt   : integer := 0;
        variable v_frame_cnt  : integer := 0;
        variable v_frame_bytes: integer := 0;
        variable v_line       : line;
        variable v_byte       : std_logic_vector(7 downto 0);
        variable v_buf0       : std_logic_vector(7 downto 0) := x"00";
        variable v_buf1       : std_logic_vector(7 downto 0) := x"00";
        variable v_buf2       : std_logic_vector(7 downto 0) := x"00";
        variable v_buf3       : std_logic_vector(7 downto 0) := x"00";
        variable v_in_frame   : boolean := false;
        file     f_log        : text;
    begin
        s_rx_fifo_pop <= '0';
        file_open(f_log, g_LOG_FILE, write_mode);
        write(v_line, string'("[FTDI PC HOST] Inicio de log"));
        writeline(f_log, v_line);
        log(ID_SEQUENCER, "PC Host driver iniciado (Modo: Solo monitorizacion, sin verificacion)", "FTDI_PC");

        loop
            wait until s_rx_fifo_level >= g_PC_READ_START_THRESHOLD;
            log(ID_SEQUENCER, "PC HOST: umbral alcanzado (" &
                to_string(s_rx_fifo_level) & " bytes) - leyendo", "FTDI_PC");

            while s_rx_fifo_empty = '0' loop

                v_byte     := s_rx_fifo_dout;
                v_byte_cnt := v_byte_cnt + 1;

                s_rx_fifo_pop <= '1';
                wait until rising_edge(s_clkout);
                s_rx_fifo_pop <= '0';

                v_buf0 := v_buf1; v_buf1 := v_buf2;
                v_buf2 := v_buf3; v_buf3 := v_byte;

                -- Deteccion de cabecera de trama (Para estructurar los mensajes por pantalla)
                if v_buf0 = c_FRAME_MARKER_0 and v_buf1 = c_FRAME_MARKER_1 and
                   v_buf2 = c_FRAME_MARKER_2 and v_buf3 = c_FRAME_MARKER_3 then

                    if v_in_frame then
                        log(ID_SEQUENCER,
                            "====== FRAME " & to_string(v_frame_cnt) &
                            " END - " & to_string(v_frame_bytes) &
                            " bytes recibidos ======", "FTDI_PC");
                        
                        write(v_line, string'("[FTDI PC HOST] FIN FRAME " &
                            integer'image(v_frame_cnt) &
                            " bytes=" & integer'image(v_frame_bytes)));
                        writeline(f_log, v_line);
                    end if;

                    v_frame_cnt   := v_frame_cnt + 1;
                    v_frame_bytes := 0;
                    v_in_frame    := true;

                    log(ID_SEQUENCER,
                        "====== FRAME " & to_string(v_frame_cnt) &
                        " START (AA 55 AA 55) ======", "FTDI_PC");
                    write(v_line, string'("[FTDI PC HOST] INICIO FRAME " &
                        integer'image(v_frame_cnt)));
                    writeline(f_log, v_line);

                elsif v_in_frame then
                    v_frame_bytes := v_frame_bytes + 1;
                end if;

                -- Imprime siempre el byte por la consola de simulación y el fichero
                log(ID_SEQUENCER, "PC HOST: Recibido Byte #" & to_string(v_byte_cnt) & 
                    " = 0x" & int_to_hex_str(to_integer(unsigned(v_byte)), 2), "FTDI_PC");

                write(v_line, string'("[" & time'image(now) &
                    "] Byte #" & integer'image(v_byte_cnt) &
                    " : 0x" & int_to_hex_str(to_integer(unsigned(v_byte)), 2)));
                writeline(f_log, v_line);

                wait for g_PC_READ_PERIOD;

            end loop;

            log(ID_SEQUENCER, "PC HOST: buffer vaciado - volviendo a idle", "FTDI_PC");

        end loop;

        file_close(f_log);
        wait;
    end process p_pc_host_driver;

    p_tx_inject : process
        constant c_TX_TABLE : t_byte_array(0 to 7) := (
            x"01", x"02", x"03", x"04", x"05", x"06", x"07", x"08"
        );
        variable v_ptr      : integer   := 0;
        variable v_tx_level : integer   := 0;
        variable v_rdn_prev : std_logic := '1';
    begin
        wait until rising_edge(s_clkout);

        if g_PC_TO_FPGA_DEPTH = 0 then
            log(ID_SEQUENCER, "TX inject: tabla vacia, RXF# permanece a '1'", "FTDI_TX");
            s_rxf_n        <= '1';
            s_tx_fifo_dout <= (others => '0');
            wait;
        end if;

        log(ID_SEQUENCER, "TX inject: cargando " &
            to_string(c_TX_TABLE'length) & " bytes en TX FIFO", "FTDI_TX");

        v_tx_level      := c_TX_TABLE'length;
        s_tx_fifo_level <= v_tx_level;
        s_tx_fifo_dout  <= c_TX_TABLE(0);
        v_ptr           := 0;
        s_rxf_n         <= '0';

        loop
            wait until rising_edge(s_clkout);

            if To_X01(acbus_io(c_FTDI_ACBUS_OE_N)) = '0' and
               To_X01(acbus_io(c_FTDI_ACBUS_RD_N)) = '0' and
               v_rdn_prev = '1' then

                if v_tx_level > 0 then
                    v_tx_level      := v_tx_level - 1;
                    s_tx_fifo_level <= v_tx_level;

                    if v_tx_level > 0 then
                        v_ptr := (v_ptr + 1) mod c_TX_TABLE'length;
                        s_tx_fifo_dout <= c_TX_TABLE(v_ptr);
                    else
                        s_tx_fifo_dout <= (others => '0');
                        if g_PC_TO_FPGA_LOOP then
                            v_tx_level      := c_TX_TABLE'length;
                            v_ptr           := 0;
                            s_tx_fifo_dout  <= c_TX_TABLE(0);
                            s_tx_fifo_level <= v_tx_level;
                            s_rxf_n         <= '0';
                            log(ID_SEQUENCER, "TX inject: tabla recargada (modo bucle)", "FTDI_TX");
                        else
                            s_rxf_n <= '1';
                            log(ID_SEQUENCER, "TX inject: tabla enviada completamente", "FTDI_TX");
                        end if;
                    end if;
                end if;

                if v_tx_level > 0 then s_rxf_n <= '0'; end if;
            end if;

            v_rdn_prev := To_X01(acbus_io(c_FTDI_ACBUS_RD_N));
        end loop;
        wait;
    end process p_tx_inject;

end architecture sim;