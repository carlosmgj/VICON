--! \file ftdi_controller.vhd
--! \brief Controlador para el FT232H en modo Synchronous FIFO.
--!
--! Envía datos continuamente desde la FIFO asíncrona hacia el PC via FTDI
--! mientras haya datos disponibles y el FTDI esté listo para recibirlos.
--!
--! Protocolo de escritura (Synchronous FIFO mode, datasheet FT232H):
--!   1. Esperar RXF# = '0'  → FTDI listo para recibir
--!   2. OE# = '0'           → FPGA toma control de ADBUS
--!   3. Poner dato en ADBUS
--!   4. WR# = '0'           → dato capturado por FTDI en flanco de subida de CLKOUT
--!   5. WR# = '1'           → fin del pulso de escritura
--!   6. Volver a 1
--!
--! Todo opera en el dominio ftdi_clk (60 MHz generado por el FT232H).
--!
--! \note Solo escritura hacia el PC implementada. Lectura desde el PC (RD#/TXE#)
--!       se añadirá cuando se implemente el canal de comandos.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ftdi_controller is
    port (
        ---------------------------------------------------------------------------
        -- Dominio ftdi_clk (60 MHz — generado por el FT232H)
        ---------------------------------------------------------------------------
        ftdi_clk    : in  std_logic;   --! Reloj 60 MHz del FTDI (ACBUS[4])
        reset       : in  std_logic;   --! Reset síncrono activo alto

        ---------------------------------------------------------------------------
        -- Interfaz con FIFO asíncrona (lado de lectura)
        ---------------------------------------------------------------------------
        fifo_dout   : in  std_logic_vector(7 downto 0);  --! Dato en cabeza de FIFO
        fifo_empty  : in  std_logic;                     --! FIFO vacía
        fifo_rd_en  : out std_logic;                     --! Pulso de lectura de FIFO

        ---------------------------------------------------------------------------
        -- Interfaz física FTDI — señales de control
        ---------------------------------------------------------------------------
        ftdi_rxf_n  : in  std_logic;   --! RXF# — '0' = FTDI listo para recibir
        ftdi_wr_n   : out std_logic;   --! WR#  — '0' = pulso de escritura
        ftdi_oe_n   : out std_logic;   --! OE#  — '0' = FPGA conduce ADBUS

        ---------------------------------------------------------------------------
        -- Interfaz física FTDI — datos
        ---------------------------------------------------------------------------
        adbus_out   : out std_logic_vector(7 downto 0);  --! Dato hacia FTDI
        adbus_oe    : out std_logic;                     --! '1' = FPGA conduce ADBUS

        ---------------------------------------------------------------------------
        -- Estado
        ---------------------------------------------------------------------------
        tx_active   : out std_logic    --! '1' durante transmisión activa
    );
end entity ftdi_controller;

architecture rtl of ftdi_controller is

    ---------------------------------------------------------------------------
    -- FSM
    ---------------------------------------------------------------------------
    type state_t is (
        ST_IDLE,        --! Esperar datos en FIFO y RXF#='0'
        ST_OE_ASSERT,   --! Asertamos OE# (1 ciclo de setup antes de WR#)
        ST_WRITE,       --! WR# = '0', dato en ADBUS
        ST_WR_HOLD,     --! WR# = '1', mantener dato 1 ciclo (hold time)
        ST_NEXT         --! Decidir si hay más datos o volver a IDLE
    );
    signal state : state_t := ST_IDLE;

    signal data_r     : std_logic_vector(7 downto 0) := (others => '0');
    signal fifo_rd_r  : std_logic := '0';

    ---------------------------------------------------------------------------
    -- ILA / Debug
    ---------------------------------------------------------------------------
    attribute mark_debug : string;
    attribute mark_debug of state      : signal is "true";
    attribute mark_debug of fifo_rd_r  : signal is "true";
    attribute mark_debug of data_r     : signal is "true";

begin

    fifo_rd_en <= fifo_rd_r;

    p_fsm : process(ftdi_clk)
    begin
        if rising_edge(ftdi_clk) then
            if reset = '1' then
                state      <= ST_IDLE;
                ftdi_wr_n  <= '1';
                ftdi_oe_n  <= '1';
                adbus_out  <= (others => '0');
                adbus_oe   <= '0';
                fifo_rd_r  <= '0';
                tx_active  <= '0';
                data_r     <= (others => '0');
            else
                fifo_rd_r <= '0';

                case state is

                    -----------------------------------------------------------
                    -- Esperar FIFO con datos y FTDI listo
                    -----------------------------------------------------------
                    when ST_IDLE =>
                        ftdi_wr_n <= '1';
                        ftdi_oe_n <= '1';
                        adbus_oe  <= '0';
                        tx_active <= '0';

                        if fifo_empty = '0' and ftdi_rxf_n = '0' then
                            -- Leer dato de la FIFO (FWFT: dato disponible en dout)
                            fifo_rd_r <= '1';
                            data_r    <= fifo_dout;
                            state     <= ST_OE_ASSERT;
                        end if;

                    -----------------------------------------------------------
                    -- Asertamos OE# — 1 ciclo de setup antes de WR#
                    -----------------------------------------------------------
                    when ST_OE_ASSERT =>
                        ftdi_oe_n <= '0';
                        adbus_oe  <= '1';
                        adbus_out <= data_r;
                        tx_active <= '1';
                        state     <= ST_WRITE;

                    -----------------------------------------------------------
                    -- Pulso WR# = '0' — FTDI captura dato en flanco de subida
                    -----------------------------------------------------------
                    when ST_WRITE =>
                        ftdi_wr_n <= '0';
                        state     <= ST_WR_HOLD;

                    -----------------------------------------------------------
                    -- WR# = '1' — hold time de 1 ciclo
                    -----------------------------------------------------------
                    when ST_WR_HOLD =>
                        ftdi_wr_n <= '1';
                        state     <= ST_NEXT;

                    -----------------------------------------------------------
                    -- ¿Hay más datos y FTDI sigue listo?
                    -----------------------------------------------------------
                    when ST_NEXT =>
                        if fifo_empty = '0' and ftdi_rxf_n = '0' then
                            fifo_rd_r <= '1';
                            data_r    <= fifo_dout;
                            state     <= ST_OE_ASSERT;
                        else
                            ftdi_oe_n <= '1';
                            adbus_oe  <= '0';
                            state     <= ST_IDLE;
                        end if;

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

end architecture rtl;
