--! \file ftdi_controller.vhd
--! \brief Controlador para el FT232H en modo Synchronous FIFO.
--!
--! Timing optimizado: 2 ciclos por byte (antes 3).
--! En ST_WRITE se baja WR# y se carga el dato simultáneamente.
--! En ST_HOLD se sube WR# y si hay más datos se vuelve a ST_WRITE directamente.

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
    -- FSM — eliminado ST_SETUP para pasar de 3 a 2 ciclos por byte
    ---------------------------------------------------------------------------
    type t_state is (
        ST_IDLE,   --! Esperar datos en FIFO y TXE#='0'
        ST_WRITE,  --! WR#='0' — FT232H captura dato en flanco de subida de CLKOUT
        ST_HOLD    --! WR#='1' — avanzar FIFO; decidir burst o volver a ST_IDLE
    );

    signal s_state : t_state := ST_IDLE;

    signal data_r    : std_logic_vector(7 downto 0) := (others => '0');
    signal fifo_rd_r : std_logic                    := '0';

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
                            data_r      <= fifo_data_i;  --! Dato estable en ADBUS
                            wr_n_o      <= '0';          --! WR# baja en el mismo ciclo
                            fifo_rd_r   <= '1';          --! Avanzar FIFO
                            tx_active_o <= '1';
                            s_state     <= ST_HOLD;
                        end if;

                    -----------------------------------------------------------
                    -- WR#='1' — decidir si continuar burst o volver a ST_IDLE
                    -----------------------------------------------------------
                    when ST_HOLD =>
                        wr_n_o <= '1';
                        if fifo_empty_i = '0' and txe_n_i = '0' then
                            data_r    <= fifo_data_i;  --! Siguiente dato
                            wr_n_o    <= '0';          --! WR# baja inmediatamente
                            fifo_rd_r <= '1';          --! Avanzar FIFO
                            s_state   <= ST_HOLD;      --! Burst continuo
                        else
                            tx_active_o <= '0';
                            s_state     <= ST_IDLE;
                        end if;

                    when others =>
                        s_state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_fsm;

end architecture rtl;