--! \file TOP_FTDI_TEST.vhd
--! \brief Top-level de test para verificar el canal FPGA → PC via FTDI FT232H.
--!
--! Envía un contador de 0x00 a 0xFF continuamente hacia el PC mientras
--! TXE# esté a '0' (FTDI listo para recibir).
--!
--! La FSM opera en el dominio CLKOUT (60 MHz, ACBUS[5]) para garantizar
--! que WR# y ADBUS están perfectamente alineados con el reloj interno del FTDI.
--!
--! El debug opera en el dominio clk (100 MHz Basys 3) para que la ILA
--! esté siempre disponible.
--!
--! OE# siempre a '1' — solo se usa para lectura FTDI→FPGA.
--! ADBUS siempre conducido por la FPGA.
--!
--! Secuencia de escritura:
--!   ST_IDLE    : Esperar TXE#='0', dato ya cargado en ADBUS
--!   ST_SETUP   : Dato estable, WR# todavía alto (1 ciclo de setup)
--!   ST_WRITE   : WR#='0' — FTDI captura dato en flanco de subida de CLKOUT
--!   ST_HOLD    : WR#='1', avanzar contador
--!
--! XDC requerido:
--!   set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {ACBUS_IBUF[5]}]
--!   create_clock -period 16.667 -name ftdi_clk [get_ports {ACBUS[5]}]

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity TOP_FTDI_TEST is
    port (
        clk   : in    std_logic;                    --! Oscilador 100 MHz Basys 3
        ACBUS : inout std_logic_vector(7 downto 0); --! Bus de control FTDI
        ADBUS : inout std_logic_vector(7 downto 0)  --! Bus de datos FTDI
    );
end entity TOP_FTDI_TEST;

architecture Behavioral of TOP_FTDI_TEST is

    ---------------------------------------------------------------------------
    -- Reloj del FTDI
    ---------------------------------------------------------------------------
    signal ftdi_clk : std_logic;

    ---------------------------------------------------------------------------
    -- FSM
    ---------------------------------------------------------------------------
    type state_t is (
        ST_IDLE,    --! Esperar TXE#='0', dato en ADBUS
        ST_SETUP,   --! Ciclo de setup — dato estable, WR# alto
        ST_WRITE,   --! WR#='0' — FTDI captura dato
        ST_HOLD     --! WR#='1', avanzar contador
    );
    signal state : state_t := ST_IDLE;

    ---------------------------------------------------------------------------
    -- Señales internas — dominio ftdi_clk
    ---------------------------------------------------------------------------
    signal counter  : unsigned(7 downto 0) := (others => '0');
    signal adbus_r  : std_logic_vector(7 downto 0) := (others => '0');
    signal wr_n_r   : std_logic := '1';
    signal txe_n_i  : std_logic;

    ---------------------------------------------------------------------------
    -- Señales de debug — dominio clk (100 MHz)
    ---------------------------------------------------------------------------
    signal debug_txe      : std_logic;
    signal debug_wr       : std_logic;
    signal debug_rxf      : std_logic;
    signal debug_adbus    : std_logic_vector(7 downto 0);
    signal debug_state    : std_logic_vector(1 downto 0);
    signal debug_cnt      : std_logic_vector(7 downto 0);

    attribute mark_debug : string;
    attribute mark_debug of debug_txe   : signal is "true";
    attribute mark_debug of debug_wr    : signal is "true";
    attribute mark_debug of debug_rxf   : signal is "true";
    attribute mark_debug of debug_adbus : signal is "true";
    attribute mark_debug of debug_state : signal is "true";
    attribute mark_debug of debug_cnt   : signal is "true";

begin

    ---------------------------------------------------------------------------
    -- CLKOUT del FTDI via BUFG
    ---------------------------------------------------------------------------
    ftdi_clk_buf : BUFG
        port map (
            I => ACBUS(5),
            O => ftdi_clk
        );

    txe_n_i <= ACBUS(1);

    ---------------------------------------------------------------------------
    -- Bus FTDI
    -- OE# siempre a '1' — no se usa para escritura
    -- ADBUS siempre conducido por la FPGA
    ---------------------------------------------------------------------------
    ADBUS    <= adbus_r;
    ACBUS(2) <= '1';    --! RD# inactivo
    ACBUS(3) <= wr_n_r; --! WR#
    ACBUS(4) <= '1';    --! SIWU# — siempre alto
    ACBUS(6) <= '1';    --! OE# — siempre inactivo para escritura
    ACBUS(0) <= 'Z';    --! RXF# — entrada
    ACBUS(1) <= 'Z';    --! TXE# — entrada
    ACBUS(7) <= '1';    --! PWRSAV# — siempre alto

    ---------------------------------------------------------------------------
    -- Debug — dominio clk (100 MHz)
    ---------------------------------------------------------------------------
    p_debug : process(clk)
    begin
        if rising_edge(clk) then
            debug_txe   <= ACBUS(1);
            debug_rxf   <= ACBUS(0);
            debug_wr    <= wr_n_r;
            debug_adbus <= adbus_r;
            debug_cnt   <= std_logic_vector(counter);

            case state is
                when ST_IDLE  => debug_state <= "00";
                when ST_SETUP => debug_state <= "01";
                when ST_WRITE => debug_state <= "10";
                when ST_HOLD  => debug_state <= "11";
                when others   => debug_state <= "00";
            end case;
        end if;
    end process p_debug;

    ---------------------------------------------------------------------------
    -- FSM — dominio ftdi_clk (60 MHz CLKOUT)
    -- Sincronizada con el reloj interno del FTDI
    ---------------------------------------------------------------------------
    p_fsm : process(ftdi_clk)
    begin
        if falling_edge(ftdi_clk) then
            case state is

                -----------------------------------------------------------
                -- Esperar TXE#='0'
                -- Dato ya cargado en ADBUS desde el ciclo anterior
                -----------------------------------------------------------
                when ST_IDLE =>
                    wr_n_r  <= '1';
                    adbus_r <= std_logic_vector(counter);
                    if txe_n_i = '0' then
                        state <= ST_SETUP;
                    end if;

                -----------------------------------------------------------
                -- Dato estable en ADBUS, WR# todavía alto
                -- Garantiza setup time antes del pulso de escritura
                -----------------------------------------------------------
                when ST_SETUP =>
                    state <= ST_WRITE;

                -----------------------------------------------------------
                -- WR#='0' — FTDI captura dato en siguiente flanco de CLKOUT
                -----------------------------------------------------------
                when ST_WRITE =>
                    wr_n_r <= '0';
                    state  <= ST_HOLD;

                -----------------------------------------------------------
                -- WR#='1' — avanzar contador
                -- Burst: si TXE#='0' continuar sin volver a ST_IDLE
                -----------------------------------------------------------
                when ST_HOLD =>
                    wr_n_r  <= '1';
                    counter <= counter + 1;
                    if txe_n_i = '0' then
                        adbus_r <= std_logic_vector(counter + 1);
                        state   <= ST_SETUP;
                    else
                        state <= ST_IDLE;
                    end if;

                when others =>
                    state <= ST_IDLE;

            end case;
        end if;
    end process p_fsm;

end architecture Behavioral;
