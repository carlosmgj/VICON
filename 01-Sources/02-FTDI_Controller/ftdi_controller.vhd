--! \file ftdi_controller.vhd
--! \brief Controlador FT232H modo Synchronous FIFO.
--!
--! TX (FPGA->PC): falling_edge — WR#/D[7:0] estables en rising_edge del FT232H
--! RX (PC->FPGA): rising_edge — adbus_i estable entre falling y siguiente rising
--!
--! Protocolo lectura (AN130):
--!   OE# >= 1 ciclo antes de RD#.
--!   RD# mantenido bajo durante toda la ráfaga.
--!   Cada flanco de rising_edge con RD#='0' hace que el FT232H avance al
--!   byte siguiente — el byte presentado es el que se colocó ANTES de ese
--!   flanco (pipeline de 1 ciclo).
--!
--!   Secuencia para N bytes:
--!     PRE  : adbus_oe='0'
--!     OE   : oe_n='0'
--!     OE2  : margen (oe_n='0' >= 1 ciclo antes de rd_n='0')
--!     RD0  : rd_n='0' — FT232H presenta byte[0] — NO leer aún (pipeline)
--!     RD1  : leer byte[0]=SYNC, FT232H presenta byte[1]
--!     RD2  : leer byte[1]=CMD,  FT232H presenta byte[2]
--!     RD3  : leer byte[2]=DH,   FT232H presenta byte[3]
--!     RD4  : leer byte[3]=DL (general,último) → soltar bus → RELEASE
--!         o  leer byte[3]=ADDR(I2C), FT232H presenta byte[4]
--!     RD5  : leer byte[4]=DH(I2C), FT232H presenta byte[5]
--!     RD6  : leer byte[5]=DL(I2C,último) → soltar bus → RELEASE
--!
--! \author Carlos Manuel Gomez Jimenez

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY ftdi_controller IS
    PORT (
        clk_i   : IN STD_LOGIC;
        reset_i : IN STD_LOGIC;

        fifo_data_i  : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
        fifo_empty_i : IN  STD_LOGIC;
        fifo_rd_en_o : OUT STD_LOGIC;

        rxf_n_i  : IN    STD_LOGIC;
        txe_n_i  : IN    STD_LOGIC;
        rd_n_o   : OUT   STD_LOGIC;
        wr_n_o   : OUT   STD_LOGIC;
        oe_n_o   : OUT   STD_LOGIC;
        adbus_i  : IN    STD_LOGIC_VECTOR(7 DOWNTO 0);
        adbus_o  : OUT   STD_LOGIC_VECTOR(7 DOWNTO 0);
        adbus_oe : OUT   STD_LOGIC;

        tx_active_o : OUT STD_LOGIC;

        cmd_valid_o : OUT STD_LOGIC;
        cmd_type_o  : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        cmd_data_o  : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        cmd_page_o  : OUT STD_LOGIC;
        cmd_addr_o  : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
END ENTITY ftdi_controller;

ARCHITECTURE rtl OF ftdi_controller IS

    CONSTANT c_CMD_SYNC : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"CC";
    CONSTANT c_CMD_I2C  : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"03";

    SIGNAL s_rx_active : STD_LOGIC := '0';

    ---------------------------------------------------------------------------
    -- TX (falling_edge)
    ---------------------------------------------------------------------------
    SIGNAL s_wr_n      : STD_LOGIC := '1';
    SIGNAL s_data_r    : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_fifo_rd   : STD_LOGIC := '0';
    SIGNAL s_tx_active : STD_LOGIC := '0';
    SIGNAL s_adbus_oe  : STD_LOGIC := '1';

    ---------------------------------------------------------------------------
    -- RX (rising_edge)
    -- Estados RDx: en cada rising_edge con RD#='0' el FT232H avanza al
    -- siguiente byte. El byte LEÍDO en RDx es el que estaba presentado
    -- ANTES de ese flanco (el FT232H lo cambia DESPUÉS del flanco).
    -- Por tanto: RD0=pipeline vacío (no leer), RD1=byte[0], RD2=byte[1]...
    ---------------------------------------------------------------------------
    TYPE t_rx_state IS (
        ST_RX_IDLE,
        ST_RX_PRE,      --! adbus_oe='0', FPGA suelta bus
        ST_RX_OE,       --! oe_n='0', FTDI conduce bus
        ST_RX_OE2,      --! margen OE# antes de RD#
        ST_RD0,         --! rd_n='0' — pipeline: FT232H presenta byte[0], no leer
        ST_RD1,         --! leer byte[0]=SYNC, FT232H avanzando a byte[1]
        ST_RD2,         --! leer byte[1]=CMD,  FT232H avanzando a byte[2]
        ST_RD3,         --! leer byte[2]=DH/PAGE, FT232H avanzando a byte[3]
        ST_RD4,         --! leer byte[3]=DL(último gral) o ADDR(I2C)
        ST_RD5,         --! leer byte[4]=DH(I2C), FT232H avanzando a byte[5]
        ST_RD6,         --! leer byte[5]=DL(I2C, último)
        ST_RX_RELEASE,  --! rd_n='1', oe_n='1', adbus_oe='1'
        ST_RX_RELEASE2, --! margen
        ST_RX_EXEC      --! emitir cmd_valid_o
    );

    SIGNAL s_rx_state    : t_rx_state := ST_RX_IDLE;
    SIGNAL s_oe_n        : STD_LOGIC := '1';
    SIGNAL s_rd_n        : STD_LOGIC := '1';
    SIGNAL s_adbus_oe_rx : STD_LOGIC := '1';
    SIGNAL s_cmd_valid_r : STD_LOGIC := '0';
    SIGNAL s_cmd_type    : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_cmd_page    : STD_LOGIC := '0';
    SIGNAL s_cmd_addr    : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_cmd_dh      : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_cmd_dl      : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_is_i2c      : STD_LOGIC := '0'; --! latcheado en RD2 para evitar comparacion multi-ciclo

BEGIN

    fifo_rd_en_o <= s_fifo_rd;
    adbus_o      <= s_data_r;
    wr_n_o       <= s_wr_n;
    oe_n_o       <= s_oe_n;
    rd_n_o       <= s_rd_n;
    adbus_oe     <= s_adbus_oe_rx WHEN s_rx_active = '1' ELSE s_adbus_oe;
    tx_active_o  <= s_tx_active;
    cmd_valid_o  <= s_cmd_valid_r;

    ---------------------------------------------------------------------------
    -- p_tx: TX imagen — falling_edge
    ---------------------------------------------------------------------------
    p_tx : PROCESS(clk_i)
    BEGIN
        IF falling_edge(clk_i) THEN
            IF reset_i = '1' THEN
                s_wr_n      <= '1';
                s_data_r    <= (OTHERS => '0');
                s_fifo_rd   <= '0';
                s_tx_active <= '0';
                s_adbus_oe  <= '1';
            ELSE
                s_fifo_rd <= '0';
                s_wr_n    <= '1';
                IF s_rx_active = '0' THEN
                    s_adbus_oe <= '1';
                    IF fifo_empty_i = '0' AND txe_n_i = '0' THEN
                        s_data_r    <= fifo_data_i;
                        s_wr_n      <= '0';
                        s_fifo_rd   <= '1';
                        s_tx_active <= '1';
                    ELSE
                        s_tx_active <= '0';
                    END IF;
                ELSE
                    s_adbus_oe  <= '0';
                    s_tx_active <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS p_tx;

    ---------------------------------------------------------------------------
    -- p_rx: RX comandos — rising_edge
    ---------------------------------------------------------------------------
    p_rx : PROCESS(clk_i)
    BEGIN
        IF rising_edge(clk_i) THEN
            IF reset_i = '1' THEN
                s_rx_state    <= ST_RX_IDLE;
                s_rx_active   <= '0';
                s_oe_n        <= '1';
                s_rd_n        <= '1';
                s_adbus_oe_rx <= '1';
                s_cmd_valid_r <= '0';
                s_cmd_type    <= (OTHERS => '0');
                s_cmd_page    <= '0';
                s_cmd_addr    <= (OTHERS => '0');
                s_cmd_dh      <= (OTHERS => '0');
                s_cmd_dl      <= (OTHERS => '0');
                s_is_i2c      <= '0';
                cmd_type_o    <= (OTHERS => '0');
                cmd_data_o    <= (OTHERS => '0');
                cmd_page_o    <= '0';
                cmd_addr_o    <= (OTHERS => '0');
            ELSE
                s_cmd_valid_r <= '0';

                CASE s_rx_state IS

                    WHEN ST_RX_IDLE =>
                        s_rx_active   <= '0';
                        s_oe_n        <= '1';
                        s_rd_n        <= '1';
                        s_adbus_oe_rx <= '1';
                        IF rxf_n_i = '0' THEN
                            s_rx_active <= '1';
                            s_rx_state  <= ST_RX_PRE;
                        END IF;

                    WHEN ST_RX_PRE =>
                        s_adbus_oe_rx <= '0';
                        s_oe_n        <= '1';
                        s_rd_n        <= '1';
                        s_rx_state    <= ST_RX_OE;

                    WHEN ST_RX_OE =>
                        s_oe_n     <= '0';
                        s_rx_state <= ST_RX_OE2;

                    WHEN ST_RX_OE2 =>
                        s_rd_n     <= '0';
                        s_rx_state <= ST_RD0;

                    --! RD0: rd_n='0' recién activado.
                    --! FT232H presenta byte[0]=SYNC pero aún puede no estar
                    --! estable (pipeline): no leer, esperar 1 ciclo.
                    WHEN ST_RD0 =>
                        s_rx_state <= ST_RD1;

                    --! RD1: byte[0]=SYNC estable en adbus_i.
                    --! Este rising_edge hace que el FT232H avance a byte[1].
                    WHEN ST_RD1 =>
                        IF adbus_i = c_CMD_SYNC THEN
                            s_rx_state <= ST_RD2;
                        ELSE
                            -- No es SYNC: soltar bus y volver a IDLE
                            s_rd_n        <= '1';
                            s_oe_n        <= '1';
                            s_adbus_oe_rx <= '1';
                            s_rx_state    <= ST_RX_RELEASE;
                        END IF;

                    --! RD2: byte[1]=CMD estable. Latchear.
                    --! FT232H avanza a byte[2].
                    WHEN ST_RD2 =>
                        s_cmd_type <= adbus_i;
                        IF adbus_i = c_CMD_I2C THEN
                            s_is_i2c <= '1';
                        ELSE
                            s_is_i2c <= '0';
                        END IF;
                        s_rx_state <= ST_RD3;

                    --! RD3: byte[2]=DATA_H (general) o PAGE (I2C). Latchear.
                    --! FT232H avanza a byte[3].
                    WHEN ST_RD3 =>
                        IF s_is_i2c = '1' THEN
                            s_cmd_page <= adbus_i(0);
                        ELSE
                            s_cmd_dh <= adbus_i;
                        END IF;
                        s_rx_state <= ST_RD4;

                    --! RD4: byte[3]=DATA_L (general, ÚLTIMO) o ADDR (I2C).
                    WHEN ST_RD4 =>
                        IF s_is_i2c = '1' THEN
                            s_cmd_addr <= adbus_i;
                            s_rx_state <= ST_RD5;  -- I2C: continuar
                        ELSE
                            s_cmd_dl      <= adbus_i;
                            s_rd_n        <= '1';
                            s_oe_n        <= '1';
                            s_adbus_oe_rx <= '1';
                            s_rx_state    <= ST_RX_RELEASE;
                        END IF;

                    --! RD5: byte[4]=DATA_H (I2C). Latchear.
                    --! FT232H avanza a byte[5].
                    WHEN ST_RD5 =>
                        s_cmd_dh   <= adbus_i;
                        s_rx_state <= ST_RD6;

                    --! RD6: byte[5]=DATA_L (I2C, ÚLTIMO).
                    WHEN ST_RD6 =>
                        s_cmd_dl      <= adbus_i;
                        s_rd_n        <= '1';
                        s_oe_n        <= '1';
                        s_adbus_oe_rx <= '1';
                        s_rx_state    <= ST_RX_RELEASE;

                    WHEN ST_RX_RELEASE =>
                        s_rx_state <= ST_RX_RELEASE2;

                    WHEN ST_RX_RELEASE2 =>
                        -- Si llegamos aquí con SYNC fallido (no I2C, no gral):
                        -- s_cmd_type = 0 → ir a IDLE sin EXEC
                        IF s_cmd_type = (s_cmd_type'RANGE => '0') AND s_is_i2c = '0' THEN
                            s_rx_active <= '0';
                            s_rx_state  <= ST_RX_IDLE;
                        ELSE
                            s_rx_state  <= ST_RX_EXEC;
                        END IF;

                    WHEN ST_RX_EXEC =>
                        s_cmd_valid_r <= '1';
                        cmd_type_o    <= s_cmd_type;
                        cmd_data_o    <= s_cmd_dh & s_cmd_dl;
                        cmd_page_o    <= s_cmd_page;
                        cmd_addr_o    <= s_cmd_addr;
                        s_rx_active   <= '0';
                        s_rx_state    <= ST_RX_IDLE;

                    WHEN OTHERS =>
                        s_rx_active <= '0';
                        s_rx_state  <= ST_RX_IDLE;

                END CASE;
            END IF;
        END IF;
    END PROCESS p_rx;

END ARCHITECTURE rtl;
