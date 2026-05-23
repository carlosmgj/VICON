--! \file ftdi_controller.vhd
--! \brief Controlador para el FT232H en modo Synchronous FIFO.
--!
--! Envía datos continuamente desde la FIFO asíncrona hacia el PC via FTDI
--! mientras haya datos disponibles y el FTDI esté listo para recibirlos.
--!
--! Lecciones aprendidas del proyecto de test TOP_FTDI_TEST:
--!   - La FSM debe operar en **falling_edge(ftdi_clk)** para garantizar
--!     que WR# y ADBUS están estables cuando el FTDI los muestrea en el
--!     flanco de subida de CLKOUT (medio ciclo de margen = 8.3 ns).
--!   - OE# debe estar siempre a '1' para escritura FPGA→FTDI.
--!     OE# solo se usa para lectura FTDI→FPGA.
--!   - ADBUS debe ser conducido siempre por la FPGA (sin tristate).
--!   - Burst mode: no volver a ST_IDLE entre bytes si TXE#='0'.
--!
--! Protocolo de escritura (Synchronous FIFO mode, datasheet FT232H):
--!   1. Esperar TXE#='0'  → FTDI listo para recibir
--!   2. Dato estable en ADBUS (ST_SETUP)
--!   3. WR#='0'           → dato capturado por FTDI en flanco de subida de CLKOUT
--!   4. WR#='1'           → fin del pulso de escritura
--!   5. Burst: si TXE#='0' → cargar siguiente dato y volver a 2
--!
--! Todo opera en falling_edge(ftdi_clk) (60 MHz generado por el FT232H).

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ftdi_controller is
    port (
        ---------------------------------------------------------------------------
        -- Dominio ftdi_clk (60 MHz — generado por el FT232H)
        ---------------------------------------------------------------------------
        ftdi_clk    : in  std_logic;   --! Reloj 60 MHz del FTDI (ACBUS[5])
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
        ftdi_txe_n  : in  std_logic;   --! TXE# — '0' = FTDI listo para recibir
        ftdi_wr_n   : out std_logic;   --! WR#  — '0' = pulso de escritura

        ---------------------------------------------------------------------------
        -- Interfaz física FTDI — datos
        ---------------------------------------------------------------------------
        adbus_out   : out std_logic_vector(7 downto 0);  --! Dato hacia FTDI

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
        ST_IDLE,    --! Esperar datos en FIFO y TXE#='0'
        ST_SETUP,   --! Dato estable en ADBUS, WR# todavía alto
        ST_WRITE,   --! WR#='0' — FTDI captura dato
        ST_HOLD     --! WR#='1' — avanzar FIFO, decidir burst o IDLE
    );
    signal state : state_t := ST_IDLE;

    signal data_r    : std_logic_vector(7 downto 0) := (others => '0');
    signal fifo_rd_r : std_logic := '0';

    ---------------------------------------------------------------------------
    -- ILA / Debug
    ---------------------------------------------------------------------------
    attribute mark_debug : string;
    attribute mark_debug of state      : signal is "true";
    attribute mark_debug of fifo_rd_r  : signal is "true";
    attribute mark_debug of data_r     : signal is "true";

begin

    fifo_rd_en <= fifo_rd_r;
    adbus_out  <= data_r;

    ---------------------------------------------------------------------------
    -- FSM — falling_edge para garantizar setup/hold time con CLKOUT
    ---------------------------------------------------------------------------
    p_fsm : process(ftdi_clk)
    begin
        if falling_edge(ftdi_clk) then
            if reset = '1' then
                state      <= ST_IDLE;
                ftdi_wr_n  <= '1';
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
                        tx_active <= '0';

                        if fifo_empty = '0' and ftdi_txe_n = '0' then
                            fifo_rd_r <= '1';
                            data_r    <= fifo_dout;
                            state     <= ST_SETUP;
                        end if;

                    -----------------------------------------------------------
                    -- Dato estable en ADBUS, WR# todavía alto
                    -----------------------------------------------------------
                    when ST_SETUP =>
                        tx_active <= '1';
                        state     <= ST_WRITE;

                    -----------------------------------------------------------
                    -- WR#='0' — FTDI captura dato en flanco de subida de CLKOUT
                    -----------------------------------------------------------
                    when ST_WRITE =>
                        ftdi_wr_n <= '0';
                        state     <= ST_HOLD;

                    -----------------------------------------------------------
                    -- WR#='1' — decidir si continuar burst o volver a IDLE
                    -----------------------------------------------------------
                    when ST_HOLD =>
                        ftdi_wr_n <= '1';
                        if fifo_empty = '0' and ftdi_txe_n = '0' then
                            fifo_rd_r <= '1';
                            data_r    <= fifo_dout;
                            state     <= ST_SETUP;
                        else
                            state <= ST_IDLE;
                        end if;

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

end architecture rtl;
