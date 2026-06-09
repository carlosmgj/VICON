--! \file ftdi_controller.vhd
--! \brief Controlador para el FT232H en modo Synchronous FIFO.
--!
--! Soporta transmisión de imagen (FPGA→PC) y recepción de comandos (PC→FPGA).
--! Los comandos tienen prioridad sobre la imagen.
--!
--! Protocolo PC→FPGA:
--!   Comando general (4 bytes): [0xCC] [CMD] [DATA_H] [DATA_L]
--!   Comando I2C   (6 bytes):   [0xCC] [0x03] [PAGE] [ADDR] [DATA_H] [DATA_L]
--!
--! CMD:
--!   0x01 → LEDs        DATA[15:0] = máscara 16 LEDs
--!   0x02 → BCD 7seg    DATA[15:0] = 4 dígitos BCD (4 bits cada uno)
--!   0x03 → Reg I2C     PAGE, ADDR, DATA[15:0]
--!   0x04 → Control cap DATA[0] = capture_en
--!
--! Secuencia lectura Sync FIFO (4 fases):
--!   ST_RX_OE      OE_N='0', setup 1 ciclo
--!   ST_RX_RD      RD_N='0', esperar 1 ciclo
--!   ST_RX_CAPTURE capturar ADBUS
--!   ST_RX_RELEASE RD_N='1', OE_N='1', ir al estado destino guardado en s_rx_dest
--!
--! Diseño RX:
--!   s_rx_dest guarda el estado al que debe ir ST_RX_RELEASE tras leer cada byte.
--!   Cada ST_CMD_BYTEx procesa s_rx_byte (ya válido) y si necesita más bytes
--!   establece s_rx_dest y lanza ST_RX_OE directamente.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ftdi_controller is
    port (
        ---------------------------------------------------------------------------
        -- Dominio clk_i (60 MHz — generado por el FT232H vía BUFG)
        ---------------------------------------------------------------------------
        clk_i   : in std_logic;
        reset_i : in std_logic;

        ---------------------------------------------------------------------------
        -- Interfaz con FIFO de imagen (lado lectura — dominio clk_i)
        ---------------------------------------------------------------------------
        fifo_data_i  : in  std_logic_vector(7 downto 0);
        fifo_empty_i : in  std_logic;
        fifo_rd_en_o : out std_logic;

        ---------------------------------------------------------------------------
        -- Interfaz física FT232H
        ---------------------------------------------------------------------------
        rxf_n_i  : in    std_logic;                     --! RXF# '0'=dato disponible del PC
        txe_n_i  : in    std_logic;                     --! TXE# '0'=FT232H listo para recibir
        rd_n_o   : out   std_logic;                     --! RD#  '0'=leer byte de ADBUS
        wr_n_o   : out   std_logic;                     --! WR#  '0'=escribir byte en ADBUS
        oe_n_o   : out   std_logic;                     --! OE#  '0'=FTDI pone dato en ADBUS
        adbus_i  : in    std_logic_vector(7 downto 0);  --! ADBUS entrada (cuando OE#='0')
        adbus_o  : out   std_logic_vector(7 downto 0);  --! ADBUS salida  (cuando escribimos)
        adbus_oe : out   std_logic;                     --! '1'=FPGA conduce ADBUS, '0'=tristate

        ---------------------------------------------------------------------------
        -- Estado TX
        ---------------------------------------------------------------------------
        tx_active_o : out std_logic;

        ---------------------------------------------------------------------------
        -- Comandos decodificados (dominio clk_i — sincronizar en TOP antes de usar)
        ---------------------------------------------------------------------------
        cmd_valid_o : out std_logic;                     --! Pulso 1 ciclo: comando listo
        cmd_type_o  : out std_logic_vector(7 downto 0); --! Tipo de comando
        cmd_data_o  : out std_logic_vector(15 downto 0);--! Payload general
        cmd_page_o  : out std_logic;                     --! Page (solo CMD 0x03)
        cmd_addr_o  : out std_logic_vector(7 downto 0)  --! Addr (solo CMD 0x03)
    );
end entity ftdi_controller;

architecture rtl of ftdi_controller is

    ---------------------------------------------------------------------------
    -- Constantes de protocolo
    ---------------------------------------------------------------------------
    constant c_CMD_SYNC : std_logic_vector(7 downto 0) := x"CC";
    constant c_CMD_LED  : std_logic_vector(7 downto 0) := x"01";
    constant c_CMD_BCD  : std_logic_vector(7 downto 0) := x"02";
    constant c_CMD_I2C  : std_logic_vector(7 downto 0) := x"03";
    constant c_CMD_CAP  : std_logic_vector(7 downto 0) := x"04";

    ---------------------------------------------------------------------------
    -- FSM
    ---------------------------------------------------------------------------
    type t_state is (
        -- TX imagen
        ST_IDLE,
        ST_HOLD,
        -- RX bus — 4 fases para leer un byte del FTDI
        ST_RX_OE,       --! OE_N='0', FTDI empieza a conducir, FPGA aún conduce
        ST_RX_OE2,      --! adbus_oe='0', FPGA suelta bus — FTDI ya conduce
        ST_RX_RD,       --! RD_N='0', capturar ADBUS en s_rx_byte
        ST_RX_RELEASE,  --! RD_N='1', OE_N='1', adbus_oe='1' → ir a s_rx_dest
        -- RX decodificación
        ST_CMD_BYTE1,   --! Verifica 0xCC
        ST_CMD_BYTE2,   --! Guarda CMD
        ST_CMD_BYTE3,   --! Guarda DATA_H o PAGE(I2C)
        ST_CMD_BYTE4,   --! Guarda DATA_L o ADDR(I2C)
        ST_CMD_BYTE5,   --! Guarda DATA_H (solo I2C)
        ST_CMD_BYTE6,   --! Guarda DATA_L (solo I2C) → EXEC
        ST_CMD_EXEC     --! Emitir cmd_valid_o
    );

    signal s_state   : t_state := ST_IDLE;
    signal s_rx_dest : t_state := ST_IDLE; --! Destino tras ST_RX_RELEASE

    ---------------------------------------------------------------------------
    -- Registros TX
    ---------------------------------------------------------------------------
    signal data_r    : std_logic_vector(7 downto 0) := (others => '0');
    signal fifo_rd_r : std_logic                    := '0';

    ---------------------------------------------------------------------------
    -- Registros de control bus — internos para poder conectarlos a la ILA
    ---------------------------------------------------------------------------
    signal s_rd_n         : std_logic := '1';  --! Registro interno RD#
    signal s_wr_n         : std_logic := '1';  --! Registro interno WR#
    signal s_oe_n         : std_logic := '1';  --! Registro interno OE#
    signal s_cmd_valid_r  : std_logic := '0';  --! Registro interno cmd_valid

    ---------------------------------------------------------------------------
    -- Registros RX
    ---------------------------------------------------------------------------
    signal s_rx_byte  : std_logic_vector(7 downto 0) := (others => '0');
    signal s_cmd_type : std_logic_vector(7 downto 0) := (others => '0');
    signal s_cmd_page : std_logic                    := '0';
    signal s_cmd_addr : std_logic_vector(7 downto 0) := (others => '0');
    signal s_cmd_dh   : std_logic_vector(7 downto 0) := (others => '0');
    signal s_cmd_dl   : std_logic_vector(7 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Timeout espera RXF# (255 ciclos a 60MHz ≈ 4µs)
    ---------------------------------------------------------------------------
    signal s_rx_timeout : integer range 0 to 255 := 0;

begin

    fifo_rd_en_o <= fifo_rd_r;
    adbus_o      <= data_r;
    rd_n_o       <= s_rd_n;
    wr_n_o       <= s_wr_n;
    oe_n_o       <= s_oe_n;
    cmd_valid_o  <= s_cmd_valid_r;

    ---------------------------------------------------------------------------
    -- FSM — rising_edge (setup/hold del FT232H cubierto con medio periodo a 60 MHz)
    ---------------------------------------------------------------------------
    p_fsm : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if reset_i = '1' then
                s_state      <= ST_IDLE;
                s_wr_n <= '1';
                s_rd_n <= '1';
                s_oe_n <= '1';
                adbus_oe     <= '1';
                fifo_rd_r    <= '0';
                tx_active_o  <= '0';
                s_cmd_valid_r <= '0';
                data_r       <= (others => '0');
                s_rx_dest    <= ST_IDLE;
                s_rx_byte    <= (others => '0');
                s_cmd_type   <= (others => '0');
                s_cmd_page   <= '0';
                s_cmd_addr   <= (others => '0');
                s_cmd_dh     <= (others => '0');
                s_cmd_dl     <= (others => '0');
                cmd_type_o   <= (others => '0');
                cmd_data_o   <= (others => '0');
                cmd_page_o   <= '0';
                cmd_addr_o   <= (others => '0');
                s_rx_timeout <= 0;
            else
                fifo_rd_r   <= '0';
                s_cmd_valid_r <= '0';

                case s_state is

                    -----------------------------------------------------------
                    -- IDLE: prioridad comandos > imagen
                    -----------------------------------------------------------
                    when ST_IDLE =>
                        s_wr_n <= '1';
                        s_rd_n <= '1';
                        s_oe_n <= '1';
                        adbus_oe    <= '1';
                        tx_active_o <= '0';
                        if rxf_n_i = '0' then
                            -- Comando entrante — leer primer byte (debe ser 0xCC)
                            s_rx_dest    <= ST_CMD_BYTE1;
                            s_rx_timeout <= 0;
                            s_state      <= ST_RX_OE;
                        elsif fifo_empty_i = '0' and txe_n_i = '0' then
                            data_r      <= fifo_data_i;
                            s_wr_n <= '0';
                            fifo_rd_r   <= '1';
                            tx_active_o <= '1';
                            adbus_oe    <= '1';
                            s_state     <= ST_HOLD;
                        end if;

                    -----------------------------------------------------------
                    -- ST_HOLD: burst TX imagen — prioridad comandos
                    -----------------------------------------------------------
                    when ST_HOLD =>
                        s_wr_n <= '1';
                        if rxf_n_i = '0' then
                            tx_active_o  <= '0';
                            s_rx_dest    <= ST_CMD_BYTE1;
                            s_rx_timeout <= 0;
                            s_state      <= ST_RX_OE;
                        elsif fifo_empty_i = '0' and txe_n_i = '0' then
                            data_r    <= fifo_data_i;
                            s_wr_n <= '0';
                            fifo_rd_r <= '1';
                            s_state   <= ST_HOLD;
                        else
                            tx_active_o <= '0';
                            s_state     <= ST_IDLE;
                        end if;

                    -----------------------------------------------------------
                    -- RX fase 1: OE_N='0' — FTDI empieza a conducir ADBUS
                    --            FPGA aún conduce (adbus_oe='1')
                    -----------------------------------------------------------
                    when ST_RX_OE =>
                        s_wr_n   <= '1';
                        s_oe_n   <= '0';     --! FTDI empieza a preparar dato
                        s_rd_n   <= '1';
                        s_state  <= ST_RX_OE2;

                    -----------------------------------------------------------
                    -- RX fase 2: adbus_oe='0' — FPGA suelta bus
                    --            FTDI ya conduce, bus estable
                    -----------------------------------------------------------
                    when ST_RX_OE2 =>
                        adbus_oe <= '0';     --! FPGA suelta un ciclo después
                        s_state  <= ST_RX_RD;

                    -----------------------------------------------------------
                    -- RX fase 2: RD_N='0' — dato estable en ADBUS, capturar
                    -----------------------------------------------------------
                    when ST_RX_RD =>
                        s_rd_n    <= '0';
                        s_rx_byte <= adbus_i;  --! capturar mientras RD_N='0'
                        s_state   <= ST_RX_RELEASE;

                    -----------------------------------------------------------
                    -- RX fase 3: RD_N='1', OE_N='1' — liberar bus, ir a destino
                    -----------------------------------------------------------
                    when ST_RX_RELEASE =>
                        s_rd_n   <= '1';
                        s_oe_n   <= '1';
                        adbus_oe <= '1';
                        s_state  <= s_rx_dest;

                    -----------------------------------------------------------
                    -- BYTE1: verifica que el byte recibido es 0xCC
                    -----------------------------------------------------------
                    when ST_CMD_BYTE1 =>
                        if s_rx_byte = c_CMD_SYNC then
                            -- Leer siguiente byte (CMD)
                            s_rx_dest    <= ST_CMD_BYTE2;
                            s_rx_timeout <= 0;
                            s_state      <= ST_RX_OE;
                        else
                            s_state <= ST_IDLE;  -- no era sync, descartar
                        end if;

                    -----------------------------------------------------------
                    -- BYTE2: guarda CMD, lanza lectura DATA_H
                    -----------------------------------------------------------
                    when ST_CMD_BYTE2 =>
                        s_cmd_type   <= s_rx_byte;
                        s_rx_dest    <= ST_CMD_BYTE3;
                        s_rx_timeout <= 0;
                        s_state      <= ST_RX_OE;

                    -----------------------------------------------------------
                    -- BYTE3: guarda DATA_H (general) o PAGE (I2C)
                    -----------------------------------------------------------
                    when ST_CMD_BYTE3 =>
                        if s_cmd_type = c_CMD_I2C then
                            s_cmd_page <= s_rx_byte(0);
                        else
                            s_cmd_dh <= s_rx_byte;
                        end if;
                        s_rx_dest    <= ST_CMD_BYTE4;
                        s_rx_timeout <= 0;
                        s_state      <= ST_RX_OE;

                    -----------------------------------------------------------
                    -- BYTE4: guarda DATA_L (general) → EXEC, o ADDR (I2C) → BYTE5
                    -----------------------------------------------------------
                    when ST_CMD_BYTE4 =>
                        if s_cmd_type = c_CMD_I2C then
                            s_cmd_addr   <= s_rx_byte;
                            s_rx_dest    <= ST_CMD_BYTE5;
                            s_rx_timeout <= 0;
                            s_state      <= ST_RX_OE;
                        else
                            s_cmd_dl <= s_rx_byte;
                            s_state  <= ST_CMD_EXEC;
                        end if;

                    -----------------------------------------------------------
                    -- BYTE5: guarda DATA_H (I2C), lanza lectura DATA_L
                    -----------------------------------------------------------
                    when ST_CMD_BYTE5 =>
                        s_cmd_dh     <= s_rx_byte;
                        s_rx_dest    <= ST_CMD_BYTE6;
                        s_rx_timeout <= 0;
                        s_state      <= ST_RX_OE;

                    -----------------------------------------------------------
                    -- BYTE6: guarda DATA_L (I2C) → EXEC
                    -----------------------------------------------------------
                    when ST_CMD_BYTE6 =>
                        s_cmd_dl <= s_rx_byte;
                        s_state  <= ST_CMD_EXEC;

                    -----------------------------------------------------------
                    -- EXEC: emitir cmd_valid_o con el comando decodificado
                    -----------------------------------------------------------
                    when ST_CMD_EXEC =>
                        s_cmd_valid_r <= '1';
                        cmd_type_o  <= s_cmd_type;
                        cmd_data_o  <= s_cmd_dh & s_cmd_dl;
                        cmd_page_o  <= s_cmd_page;
                        cmd_addr_o  <= s_cmd_addr;
                        s_state     <= ST_IDLE;

                    when others =>
                        s_state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

end architecture rtl;