--! \file ftdi_agent.vhd
--! \brief Agente de simulacion del chip FT232H en modo Synchronous FIFO 245 con host PC asincrono.
--!
--! Para inyectar comandos PC->FPGA, edita la tabla c_CMD_TABLE mas abajo.
--! Protocolo de comandos:
--!   General (4 bytes): [0xCC] [CMD] [DATA_H] [DATA_L]
--!   I2C     (6 bytes): [0xCC] [0x03] [PAGE] [ADDR] [DATA_H] [DATA_L]
--!
--! CMD:
--!   0x01 -> LEDs        DATA[15:0] = mascara 16 LEDs
--!   0x02 -> BCD 7seg    DATA[15:0] = 4 digitos BCD
--!   0x03 -> Reg I2C     PAGE, ADDR, DATA[15:0]
--!   0x04 -> Control cap DATA[0] = capture_en

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
        g_PC_READ_PERIOD          : time    := 100 ns
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

    constant c_CMD_SYNC : std_logic_vector(7 downto 0) := x"CC";
    constant c_CMD_LED  : std_logic_vector(7 downto 0) := x"01";
    constant c_CMD_BCD  : std_logic_vector(7 downto 0) := x"02";
    constant c_CMD_I2C  : std_logic_vector(7 downto 0) := x"03";
    constant c_CMD_CAP  : std_logic_vector(7 downto 0) := x"04";

    type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    ---------------------------------------------------------------------------
    -- TABLA DE COMANDOS A INYECTAR (PC -> FPGA)
    --
    -- Cada fila es un comando ya serializado en bytes (longitud variable).
    -- Edita esta tabla para configurar los comandos del test:
    --
    -- Ejemplos:
    --   Toggle LED 15 (CMD 0x01, dato indiferente):
    --     (4, (CC, 01, 00, 00, 00, 00))
    --
    --   Escribir reg I2C: page=Core(0), addr=0x05, data=0x0084:
    --     (6, (CC, 03, 00, 05, 00, 84))
    --
    -- El primer campo es la longitud real (4 o 6); el resto del array
    -- se rellena con ceros y se ignora.
    ---------------------------------------------------------------------------
    type t_cmd_entry is record
        len   : integer;
        bytes : t_byte_array(0 to 5);
    end record;
    type t_cmd_table is array (natural range <>) of t_cmd_entry;

    constant c_CMD_TABLE : t_cmd_table := (
        -- Comando 0: Toggle LED 15
        0 => (len => 4, bytes => (x"CC", x"01", x"00", x"00", x"00", x"00")),
        1 => (len => 4, bytes => (x"CC", x"01", x"00", x"00", x"00", x"00"))

        -- Descomenta y ajusta para mas comandos:
        --,1 => (len => 6, bytes => (x"CC", x"03", x"00", x"05", x"00", x"84"))
    );

    constant c_CMD_START_DELAY : time := 350 us;  --! Espera antes del primer comando
    constant c_CMD_GAP         : time := 200 us;   --! Espera entre comandos

    -- FIFO RX real (FPGA->PC): array circular con punteros wr/rd
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

    signal s_tx_fifo_dout : std_logic_vector(7 downto 0) := (others => '0');

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

    ---------------------------------------------------------------------------
    -- p_rx_fifo_ctrl: gestiona punteros y nivel de la FIFO RX (FPGA->PC)
    ---------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------
    -- p_clkout: Generador de CLKOUT 60 MHz
    ---------------------------------------------------------------------------
    p_clkout : process
    begin
        loop
            s_clkout <= '0'; wait for c_FTDI_CLK_PERIOD / 2;
            s_clkout <= '1'; wait for c_FTDI_CLK_PERIOD / 2;
        end loop;
    end process p_clkout;

    ---------------------------------------------------------------------------
    -- p_txe: Control de TXE# segun nivel de la FIFO RX
    ---------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------
    -- p_rx: Captura bytes FPGA->PC y los mete en la FIFO RX
    ---------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------
    -- p_pc_host_driver: Simula el PC leyendo la FIFO RX y logueando bytes
    ---------------------------------------------------------------------------
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
        log(ID_SEQUENCER, "PC Host driver iniciado (Modo: Solo monitorizacion)", "FTDI_PC");

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

    ---------------------------------------------------------------------------
    -- p_tx_inject: Inyeccion de comandos PC->FPGA segun c_CMD_TABLE
    ---------------------------------------------------------------------------
    p_tx_inject : process
        variable v_idx      : integer;
        variable v_rdn_prev : std_logic := '1';
    begin
        s_rxf_n        <= '1';
        s_tx_fifo_dout <= (others => '0');

        if c_CMD_TABLE'length = 0 then
            log(ID_SEQUENCER, "TX inject: tabla de comandos vacia, RXF# permanece a '1'", "FTDI_TX");
            wait;
        end if;

        wait for c_CMD_START_DELAY;

        for c in c_CMD_TABLE'range loop

            log(ID_SEQUENCER, "TX inject: comando " & to_string(c) &
                " (" & to_string(c_CMD_TABLE(c).len) & " bytes) -> 0x" &
                int_to_hex_str(to_integer(unsigned(c_CMD_TABLE(c).bytes(1))), 2),
                "FTDI_TX");

            v_idx := 0;
            s_tx_fifo_dout <= c_CMD_TABLE(c).bytes(0);
            s_rxf_n        <= '0';
            v_rdn_prev     := '1';

            while v_idx < c_CMD_TABLE(c).len loop
                wait until rising_edge(s_clkout);

                if To_X01(acbus_io(c_FTDI_ACBUS_OE_N)) = '0' and
                   To_X01(acbus_io(c_FTDI_ACBUS_RD_N)) = '0' and
                   v_rdn_prev = '1' then

                    log(ID_SEQUENCER, "TX inject: byte enviado #" & to_string(v_idx) &
                        " = 0x" & int_to_hex_str(
                            to_integer(unsigned(c_CMD_TABLE(c).bytes(v_idx))), 2),
                        "FTDI_TX");

                    v_idx := v_idx + 1;
                    if v_idx < c_CMD_TABLE(c).len then
                        s_tx_fifo_dout <= c_CMD_TABLE(c).bytes(v_idx);
                    else
                        s_tx_fifo_dout <= (others => '0');
                        s_rxf_n        <= '1';
                    end if;
                end if;

                v_rdn_prev := To_X01(acbus_io(c_FTDI_ACBUS_RD_N));
            end loop;

            log(ID_SEQUENCER, "TX inject: comando " & to_string(c) & " completado", "FTDI_TX");

            if c < c_CMD_TABLE'high then
                wait for c_CMD_GAP;
            end if;

        end loop;

        log(ID_SEQUENCER, "TX inject: todos los comandos enviados", "FTDI_TX");
        wait;
    end process p_tx_inject;

end architecture sim;