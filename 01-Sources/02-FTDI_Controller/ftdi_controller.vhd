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
--!   ST_RX_OE      OE_N='0' y adbus_oe='0' a la vez (sin contencion), FTDI empieza a conducir
--!   ST_RX_OE2     margen — bus ya estable en manos del FT232H
--!   ST_RX_CAPTURE capturar ADBUS (RD_N='0')
--!   ST_RX_RELEASE RD_N='1', OE_N='1', adbus_oe='1' → ir al estado destino guardado en s_rx_dest
--!
--! Diseño RX:
--!   s_rx_dest guarda el estado al que debe ir ST_RX_RELEASE tras leer cada byte.
--!   Cada ST_CMD_BYTEx procesa s_rx_byte (ya válido) y si necesita más bytes
--!   establece s_rx_dest y lanza ST_RX_OE directamente.
--! \author Carlos Manuel Gomez Jimenez


LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY ftdi_controller IS
    PORT (
        ---------------------------------------------------------------------------
        -- Dominio clk_i (60 MHz — generado por el FT232H vía BUFG)
        ---------------------------------------------------------------------------
        clk_i   : IN STD_LOGIC;
        reset_i : IN STD_LOGIC;

        ---------------------------------------------------------------------------
        -- Interfaz con FIFO de imagen (lado lectura — dominio clk_i)
        ---------------------------------------------------------------------------
        fifo_data_i  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
        fifo_empty_i : IN  STD_LOGIC;
        fifo_rd_en_o : OUT STD_LOGIC;

        ---------------------------------------------------------------------------
        -- Interfaz física FT232H
        ---------------------------------------------------------------------------
        rxf_n_i  : IN    STD_LOGIC;                     --! RXF# '0'=dato disponible del PC
        txe_n_i  : IN    STD_LOGIC;                     --! TXE# '0'=FT232H listo para recibir
        rd_n_o   : OUT   STD_LOGIC;                     --! RD#  '0'=leer byte de ADBUS
        wr_n_o   : OUT   STD_LOGIC;                     --! WR#  '0'=escribir byte en ADBUS
        oe_n_o   : OUT   STD_LOGIC;                     --! OE#  '0'=FTDI pone dato en ADBUS
        adbus_i  : IN    STD_LOGIC_VECTOR(7 DOWNTO 0);  --! ADBUS entrada (cuando OE#='0')
        adbus_o  : OUT   STD_LOGIC_VECTOR(7 DOWNTO 0);  --! ADBUS salida  (cuando escribimos)
        adbus_oe : OUT   STD_LOGIC;                     --! '1'=FPGA conduce ADBUS, '0'=tristate

        ---------------------------------------------------------------------------
        -- Estado TX
        ---------------------------------------------------------------------------
        tx_active_o : OUT STD_LOGIC;

        ---------------------------------------------------------------------------
        -- Comandos decodificados (dominio clk_i — sincronizar en TOP antes de usar)
        ---------------------------------------------------------------------------
        cmd_valid_o : OUT STD_LOGIC;                     --! Pulso 1 ciclo: comando listo
        cmd_type_o  : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); --! Tipo de comando
        cmd_data_o  : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);--! Payload general
        cmd_page_o  : OUT STD_LOGIC;                     --! Page (solo CMD 0x03)
        cmd_addr_o  : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)  --! Addr (solo CMD 0x03)
    );
END ENTITY ftdi_controller;

ARCHITECTURE rtl OF ftdi_controller IS

    ---------------------------------------------------------------------------
    -- Constantes de protocolo
    ---------------------------------------------------------------------------
    CONSTANT c_CMD_SYNC : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"CC";
    CONSTANT c_CMD_LED  : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"01";
    CONSTANT c_CMD_BCD  : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"02";
    CONSTANT c_CMD_I2C  : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"03";
    CONSTANT c_CMD_CAP  : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"04";

    ---------------------------------------------------------------------------
    -- FSM
    ---------------------------------------------------------------------------
    TYPE t_state IS (
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

    SIGNAL s_state   : t_state := ST_IDLE;
    SIGNAL s_rx_dest : t_state := ST_IDLE; --! Destino tras ST_RX_RELEASE

    ---------------------------------------------------------------------------
    -- Registros TX
    ---------------------------------------------------------------------------
    SIGNAL data_r    : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL fifo_rd_r : STD_LOGIC                    := '0';

    ---------------------------------------------------------------------------
    -- Registros de control bus — internos para poder conectarlos a la ILA
    ---------------------------------------------------------------------------
    SIGNAL s_rd_n         : STD_LOGIC := '1';  --! Registro interno RD#
    SIGNAL s_wr_n         : STD_LOGIC := '1';  --! Registro interno WR#
    SIGNAL s_oe_n         : STD_LOGIC := '1';  --! Registro interno OE#
    SIGNAL s_cmd_valid_r  : STD_LOGIC := '0';  --! Registro interno cmd_valid

    ---------------------------------------------------------------------------
    -- Registros RX
    ---------------------------------------------------------------------------
    SIGNAL s_rx_byte  : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_cmd_type : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_cmd_page : STD_LOGIC                    := '0';
    SIGNAL s_cmd_addr : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_cmd_dh   : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_cmd_dl   : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');

    ---------------------------------------------------------------------------
    -- Timeout espera RXF# (255 ciclos a 60MHz ≈ 4µs)
    ---------------------------------------------------------------------------
    SIGNAL s_rx_timeout : integer range 0 to 255 := 0;

BEGIN

    fifo_rd_en_o <= fifo_rd_r;
    adbus_o      <= data_r;
    rd_n_o       <= s_rd_n;
    wr_n_o       <= s_wr_n;
    oe_n_o       <= s_oe_n;
    cmd_valid_o  <= s_cmd_valid_r;

    ---------------------------------------------------------------------------
    -- FSM — rising_edge (setup/hold del FT232H cubierto con medio periodo a 60 MHz)
    ---------------------------------------------------------------------------
    p_fsm : PROCESS(clk_i)
    BEGIN
        IF falling_edge(clk_i) THEN
            IF reset_i = '1' THEN
                s_state      <= ST_IDLE;
                s_wr_n <= '1';
                s_rd_n <= '1';
                s_oe_n <= '1';
                adbus_oe     <= '1';
                fifo_rd_r    <= '0';
                tx_active_o  <= '0';
                s_cmd_valid_r <= '0';
                data_r       <= (OTHERS => '0');
                s_rx_dest    <= ST_IDLE;
                s_rx_byte    <= (OTHERS => '0');
                s_cmd_type   <= (OTHERS => '0');
                s_cmd_page   <= '0';
                s_cmd_addr   <= (OTHERS => '0');
                s_cmd_dh     <= (OTHERS => '0');
                s_cmd_dl     <= (OTHERS => '0');
                cmd_type_o   <= (OTHERS => '0');
                cmd_data_o   <= (OTHERS => '0');
                cmd_page_o   <= '0';
                cmd_addr_o   <= (OTHERS => '0');
                s_rx_timeout <= 0;
            ELSE
                fifo_rd_r   <= '0';
                s_cmd_valid_r <= '0';

                CASE s_state IS

                    -----------------------------------------------------------
                    -- IDLE: prioridad comandos > imagen
                    -----------------------------------------------------------
                    WHEN ST_IDLE =>
                        s_wr_n <= '1';
                        s_rd_n <= '1';
                        s_oe_n <= '1';
                        adbus_oe    <= '1';
                        tx_active_o <= '0';
                        IF rxf_n_i = '0' THEN
                            -- Comando entrante — leer primer byte (debe ser 0xCC)
                            s_rx_dest    <= ST_CMD_BYTE1;
                            s_rx_timeout <= 0;
                            s_state      <= ST_RX_OE;
                        ELSIF fifo_empty_i = '0' AND txe_n_i = '0' THEN
                            data_r      <= fifo_data_i;
                            s_wr_n <= '0';
                            fifo_rd_r   <= '1';
                            tx_active_o <= '1';
                            adbus_oe    <= '1';
                            s_state     <= ST_HOLD;
                        END IF;

                    -----------------------------------------------------------
                    -- ST_HOLD: burst TX imagen — prioridad comandos
                    -----------------------------------------------------------
                    WHEN ST_HOLD =>
                        s_wr_n <= '1';
                        IF rxf_n_i = '0' THEN
                            tx_active_o  <= '0';
                            s_rx_dest    <= ST_CMD_BYTE1;
                            s_rx_timeout <= 0;
                            s_state      <= ST_RX_OE;
                        ELSIF fifo_empty_i = '0' AND txe_n_i = '0' THEN
                            data_r    <= fifo_data_i;
                            s_wr_n <= '0';
                            fifo_rd_r <= '1';
                            s_state   <= ST_HOLD;
                        ELSE
                            tx_active_o <= '0';
                            s_state     <= ST_IDLE;
                        END IF;

                    -----------------------------------------------------------
                    -- RX fase 1: OE_N='0' + adbus_oe='0' — la FPGA suelta el bus
                    --            en el MISMO ciclo en que pide al FT232H que lo
                    --            conduzca (evita contencion de 1 ciclo completo)
                    -----------------------------------------------------------
                    WHEN ST_RX_OE =>
                        s_wr_n   <= '1';
                        s_oe_n   <= '0';     --! FTDI empieza a preparar dato
                        adbus_oe <= '0';     --! FPGA suelta el bus a la vez
                        s_rd_n   <= '1';
                        s_state  <= ST_RX_OE2;

                    -----------------------------------------------------------
                    -- RX fase 2: margen — bus ya en manos del FT232H, estable
                    -----------------------------------------------------------
                    WHEN ST_RX_OE2 =>
                        s_state  <= ST_RX_RD;

                    -----------------------------------------------------------
                    -- RX fase 2: RD_N='0' — dato estable en ADBUS, capturar
                    -----------------------------------------------------------
                    WHEN ST_RX_RD =>
                        s_rd_n    <= '0';
                        s_rx_byte <= adbus_i;  --! capturar mientras RD_N='0'
                        s_state   <= ST_RX_RELEASE;

                    -----------------------------------------------------------
                    -- RX fase 3: RD_N='1', OE_N='1' — liberar bus, ir a destino
                    -----------------------------------------------------------
                    WHEN ST_RX_RELEASE =>
                        s_rd_n   <= '1';
                        s_oe_n   <= '1';
                        adbus_oe <= '1';
                        s_state  <= s_rx_dest;

                    -----------------------------------------------------------
                    -- BYTE1: verifica que el byte recibido es 0xCC
                    -----------------------------------------------------------
                    WHEN ST_CMD_BYTE1 =>
                        IF s_rx_byte = c_CMD_SYNC THEN
                            -- Leer siguiente byte (CMD)
                            s_rx_dest    <= ST_CMD_BYTE2;
                            s_rx_timeout <= 0;
                            s_state      <= ST_RX_OE;
                        ELSE
                            s_state <= ST_IDLE;  -- no era sync, descartar
                        END IF;

                    -----------------------------------------------------------
                    -- BYTE2: guarda CMD, lanza lectura DATA_H
                    -----------------------------------------------------------
                    WHEN ST_CMD_BYTE2 =>
                        s_cmd_type   <= s_rx_byte;
                        s_rx_dest    <= ST_CMD_BYTE3;
                        s_rx_timeout <= 0;
                        s_state      <= ST_RX_OE;

                    -----------------------------------------------------------
                    -- BYTE3: guarda DATA_H (general) o PAGE (I2C)
                    -----------------------------------------------------------
                    WHEN ST_CMD_BYTE3 =>
                        IF s_cmd_type = c_CMD_I2C THEN
                            s_cmd_page <= s_rx_byte(0);
                        ELSE
                            s_cmd_dh <= s_rx_byte;
                        END IF;
                        s_rx_dest    <= ST_CMD_BYTE4;
                        s_rx_timeout <= 0;
                        s_state      <= ST_RX_OE;

                    -----------------------------------------------------------
                    -- BYTE4: guarda DATA_L (general) → EXEC, o ADDR (I2C) → BYTE5
                    -----------------------------------------------------------
                    WHEN ST_CMD_BYTE4 =>
                        IF s_cmd_type = c_CMD_I2C THEN
                            s_cmd_addr   <= s_rx_byte;
                            s_rx_dest    <= ST_CMD_BYTE5;
                            s_rx_timeout <= 0;
                            s_state      <= ST_RX_OE;
                        ELSE
                            s_cmd_dl <= s_rx_byte;
                            s_state  <= ST_CMD_EXEC;
                        END IF;

                    -----------------------------------------------------------
                    -- BYTE5: guarda DATA_H (I2C), lanza lectura DATA_L
                    -----------------------------------------------------------
                    WHEN ST_CMD_BYTE5 =>
                        s_cmd_dh     <= s_rx_byte;
                        s_rx_dest    <= ST_CMD_BYTE6;
                        s_rx_timeout <= 0;
                        s_state      <= ST_RX_OE;

                    -----------------------------------------------------------
                    -- BYTE6: guarda DATA_L (I2C) → EXEC
                    -----------------------------------------------------------
                    WHEN ST_CMD_BYTE6 =>
                        s_cmd_dl <= s_rx_byte;
                        s_state  <= ST_CMD_EXEC;

                    -----------------------------------------------------------
                    -- EXEC: emitir cmd_valid_o con el comando decodificado
                    -----------------------------------------------------------
                    WHEN ST_CMD_EXEC =>
                        s_cmd_valid_r <= '1';
                        cmd_type_o  <= s_cmd_type;
                        cmd_data_o  <= s_cmd_dh & s_cmd_dl;
                        cmd_page_o  <= s_cmd_page;
                        cmd_addr_o  <= s_cmd_addr;
                        s_state     <= ST_IDLE;

                    WHEN OTHERS =>
                        s_state <= ST_IDLE;

                END CASE;
            END IF;
        END IF;
    END PROCESS p_fsm;

END ARCHITECTURE rtl;