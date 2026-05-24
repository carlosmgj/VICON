--! \file mt9v111_image.vhd
--! \brief Simulador de cámara MT9V111 para test del pipeline de captura.


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;

--! \brief Simulador de cámara MT9V111
--! \fsm_show_actions
entity mt9v111_image is
    generic (
        g_H_RES  : integer := c_MT9V111_H_RES;   --! Resolución horizontal en píxeles
        g_V_RES  : integer := c_MT9V111_V_RES;   --! Resolución vertical en líneas
        g_HBLANK : integer := 100;               --! Ciclos de blanking horizontal entre líneas
        g_VBLANK : integer := 1000               --! Ciclos de blanking vertical entre frames
    );
    port (
        pixclk_i  : in  std_logic;                     --! Reloj de píxel (dominio del sensor)
        reset_i   : in  std_logic;                     --! Reset síncrono activo alto
        fvalid_o  : out std_logic;                     --! Frame valid: '1' durante la transmisión de un frame
        lvalid_o  : out std_logic;                     --! Line valid: '1' durante la transmisión de una línea
        data_o    : out std_logic_vector(7 downto 0)   --! Byte de datos sintético (YCbCr intercalado)
    );
end entity mt9v111_image;

architecture rtl of mt9v111_image is

    type t_state is (
        ST_VBLANK,  --! Blanking vertical: fvalid_o='0', esperando inicio de frame
        ST_HBLANK,  --! Blanking horizontal: fvalid_o='1', lvalid_o='0', esperando inicio de línea
        ST_ACTIVE   --! Línea activa: fvalid_o='1', lvalid_o='1', generando datos YCbCr
    );

    signal s_state : t_state := ST_VBLANK;  --! Estado actual de la FSM

    signal s_col_cnt   : unsigned(10 downto 0)             := (others => '0');  --! Contador de bytes en la línea activa (par=Cb, impar=Y)
    signal s_row_cnt   : integer range 0 to g_V_RES  - 1   := 0;               --! Contador de líneas dentro del frame
    signal s_blank_cnt : integer range 0 to g_VBLANK - 1   := 0;               --! Contador de ciclos de blanking (horizontal y vertical)

    signal fvalid_r : std_logic                    := '0';              --! Registro de frame valid
    signal lvalid_r : std_logic                    := '0';              --! Registro de line valid
    signal data_r   : std_logic_vector(7 downto 0) := (others => '0'); --! Registro de dato de salida

begin

    fvalid_o <= fvalid_r;
    lvalid_o <= lvalid_r;
    data_o   <= data_r;

    --! \brief FSM generadora de timing de cámara — dominio pixclk_i
    p_sim : process(pixclk_i)
    begin
        if rising_edge(pixclk_i) then
            if reset_i = '1' then
                s_state     <= ST_VBLANK;
                s_col_cnt   <= (others => '0');
                s_row_cnt   <= 0;
                s_blank_cnt <= 0;
                fvalid_r    <= '0';
                lvalid_r    <= '0';
                data_r      <= (others => '0');
            else
                case s_state is

                    when ST_VBLANK =>
                        fvalid_r <= '0';
                        lvalid_r <= '0';
                        data_r   <= (others => '0');
                        if s_blank_cnt = g_VBLANK - 1 then
                            s_blank_cnt <= 0;
                            s_row_cnt   <= 0;
                            s_state     <= ST_HBLANK;
                        else
                            s_blank_cnt <= s_blank_cnt + 1;
                        end if;

                    when ST_HBLANK =>
                        fvalid_r <= '1';
                        lvalid_r <= '0';
                        data_r   <= (others => '0');
                        if s_blank_cnt = g_HBLANK - 1 then
                            s_blank_cnt <= 0;
                            s_col_cnt   <= (others => '0');
                            s_state     <= ST_ACTIVE;
                        else
                            s_blank_cnt <= s_blank_cnt + 1;
                        end if;

                    -----------------------------------------------------------
                    -- Línea activa — orden igual que MT9V111 real:
                    -- s_col_cnt(0)='0' → Cb = 0x80     (croma, byte par)
                    -- s_col_cnt(0)='1' → Y  = columna  (luma,  byte impar)
                    -----------------------------------------------------------
                    when ST_ACTIVE =>
                        fvalid_r <= '1';
                        lvalid_r <= '1';

                        if s_col_cnt(0) = '0' then
                            data_r <= x"80";
                        else
                            data_r <= std_logic_vector(s_col_cnt(8 downto 1));
                        end if;

                        if s_col_cnt = to_unsigned(g_H_RES * 2 - 1, 11) then
                            s_col_cnt <= (others => '0');
                            if s_row_cnt = g_V_RES - 1 then
                                s_row_cnt <= 0;
                                s_state   <= ST_VBLANK;
                            else
                                s_row_cnt <= s_row_cnt + 1;
                                s_state   <= ST_HBLANK;
                            end if;
                        else
                            s_col_cnt <= s_col_cnt + 1;
                        end if;

                    when others =>
                        s_state <= ST_VBLANK;

                end case;
            end if;
        end if;
    end process p_sim;

end architecture rtl;
