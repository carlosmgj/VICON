--! \file ftdi_controller.vhd
--! \brief Controlador para el FT232H en modo Synchronous FIFO.


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ftdi_controller is
    port (
        ---------------------------------------------------------------------------
        -- Dominio clk_i (60 MHz — generado por el FT232H vía BUFG)
        ---------------------------------------------------------------------------
        clk_i   : in std_logic;  --! Reloj 60 MHz del FT232H (ACBUS[5] vía BUFG)
        reset_i : in std_logic;  --! Reset síncrono activo alto

        ---------------------------------------------------------------------------
        -- Interfaz con FIFO asíncrona (lado de lectura — dominio clk_i)
        ---------------------------------------------------------------------------
        fifo_data_i  : in  std_logic_vector(7 downto 0);  --! Dato en cabeza de la FIFO de captura
        fifo_empty_i : in  std_logic;                     --! FIFO vacía; no hay datos disponibles para enviar
        fifo_rd_en_o : out std_logic;                     --! Pulso de lectura de FIFO (1 ciclo, activo alto)

        ---------------------------------------------------------------------------
        -- Interfaz física FT232H
        ---------------------------------------------------------------------------
        txe_n_i  : in  std_logic;                      --! TXE# (activo bajo): '0'=FT232H listo para recibir
        wr_n_o   : out std_logic;                      --! WR#  (activo bajo): '0'=pulso de escritura al FTDI
        adbus_o  : out std_logic_vector(7 downto 0);   --! Byte de datos hacia el FT232H por ADBUS

        ---------------------------------------------------------------------------
        -- Estado
        ---------------------------------------------------------------------------
        tx_active_o : out std_logic  --! '1' durante transmisión activa (burst en curso)
    );
end entity ftdi_controller;

architecture rtl of ftdi_controller is

    ---------------------------------------------------------------------------
    -- FSM
    ---------------------------------------------------------------------------
    type t_state is (
        ST_IDLE,   --! Esperar datos en FIFO y TXE#='0'
        ST_SETUP,  --! Dato estable en ADBUS; WR# todavía alto (setup time)
        ST_WRITE,  --! WR#='0' — FT232H captura dato en flanco de subida de CLKOUT
        ST_HOLD    --! WR#='1' — avanzar FIFO; decidir burst o volver a ST_IDLE
    );

    signal s_state : t_state := ST_IDLE;  --! Estado actual de la FSM

    signal data_r    : std_logic_vector(7 downto 0) := (others => '0');  --! Registro del dato a enviar por ADBUS
    signal fifo_rd_r : std_logic                    := '0';              --! Registro de habilitación de lectura de FIFO

    ---------------------------------------------------------------------------
    -- ILA / Debug
    ---------------------------------------------------------------------------
    attribute mark_debug : string;
    attribute mark_debug of s_state    : signal is "true";
    attribute mark_debug of fifo_rd_r  : signal is "true";
    attribute mark_debug of data_r     : signal is "true";

begin

    fifo_rd_en_o <= fifo_rd_r;
    adbus_o      <= data_r;

    ---------------------------------------------------------------------------
    -- FSM — falling_edge para garantizar setup/hold time respecto a CLKOUT
    ---------------------------------------------------------------------------
    p_fsm : process(clk_i)
    begin
        if falling_edge(clk_i) then
            if reset_i = '1' then
                s_state     <= ST_IDLE;
                wr_n_o      <= '1';
                fifo_rd_r   <= '0';
                tx_active_o <= '0';
                data_r      <= (others => '0');
            else
                fifo_rd_r <= '0';

                case s_state is

                    -----------------------------------------------------------
                    -- Esperar FIFO con datos y FTDI listo
                    -----------------------------------------------------------
                    when ST_IDLE =>
                        wr_n_o      <= '1';
                        tx_active_o <= '0';
                        if fifo_empty_i = '0' and txe_n_i = '0' then
                            fifo_rd_r <= '1';
                            data_r    <= fifo_data_i;
                            s_state   <= ST_SETUP;
                        end if;

                    -----------------------------------------------------------
                    -- Dato estable en ADBUS; WR# todavía alto
                    -----------------------------------------------------------
                    when ST_SETUP =>
                        tx_active_o <= '1';
                        s_state     <= ST_WRITE;

                    -----------------------------------------------------------
                    -- WR#='0' — FT232H captura dato en flanco de subida de CLKOUT
                    -----------------------------------------------------------
                    when ST_WRITE =>
                        wr_n_o  <= '0';
                        s_state <= ST_HOLD;

                    -----------------------------------------------------------
                    -- WR#='1' — decidir si continuar burst o volver a ST_IDLE
                    -----------------------------------------------------------
                    when ST_HOLD =>
                        wr_n_o <= '1';
                        if fifo_empty_i = '0' and txe_n_i = '0' then
                            fifo_rd_r <= '1';
                            data_r    <= fifo_data_i;
                            s_state   <= ST_SETUP;
                        else
                            s_state <= ST_IDLE;
                        end if;

                    when others =>
                        s_state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

end architecture rtl;
