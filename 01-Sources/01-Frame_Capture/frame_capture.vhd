--! \file frame_capture.vhd
--! \brief Capturador de frames para el sensor MT9V111.
--!
--! Escribe un marcador de inicio de frame (4 bytes: 0xAA 0x55 0xAA 0x55) seguido
--! de los píxeles Y (luminancia) de cada línea, descartando los bytes de croma.
--!
--! Sustituciones en datos de imagen para evitar falsos positivos con el marcador:
--!   0xFF → 0xFE
--!   0x00 → 0x01
--!   0xAA → 0xAB
--!   0x55 → 0x56
--!
--! En Python usar: MARKER = bytes([0xAA, 0x55, 0xAA, 0x55])

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;

entity frame_capture is
    generic (
        g_H_RES : integer := c_MT9V111_H_RES;  --! Resolución horizontal en píxeles
        g_V_RES : integer := c_MT9V111_V_RES   --! Resolución vertical en líneas
    );
    port (
        pixclk_i     : in  std_logic;                      --! Reloj de píxel del sensor MT9V111
        reset_i      : in  std_logic;                      --! Reset síncrono activo alto (dominio pixclk)
        fvalid_i     : in  std_logic;                      --! Frame valid: '1' durante la transmisión de un frame
        lvalid_i     : in  std_logic;                      --! Line valid: '1' durante la transmisión de una línea
        data_i       : in  std_logic_vector(7 downto 0);   --! Byte de datos del sensor (YCbCr intercalado)
        capture_en_i : in  std_logic;                      --! Habilitación de captura; debe estar activo antes del inicio del frame
        fifo_data_o  : out std_logic_vector(7 downto 0);   --! Byte a escribir en la FIFO asíncrona
        fifo_wr_o    : out std_logic;                      --! Habilitación de escritura en la FIFO (1 ciclo por byte)
        fifo_full_i  : in  std_logic;                      --! FIFO llena; si sube durante captura se activa overflow_o
        frame_done_o : out std_logic;                      --! Pulso de 1 ciclo al completar el frame
        overflow_o   : out std_logic                       --! '1' si la FIFO se llenó durante la captura; frame corrupto
    );
end entity frame_capture;

architecture rtl of frame_capture is

    type t_cap_state is (
        ST_IDLE,              --! Esperando capture_en_i activo
        ST_WAIT_FRAME_START,  --! Esperando flanco de subida de fvalid_i
        ST_MARKER_0,          --! Escribiendo marcador byte 0: c_FRAME_MARKER_0
        ST_MARKER_1,          --! Escribiendo marcador byte 1: c_FRAME_MARKER_1
        ST_MARKER_2,          --! Escribiendo marcador byte 2: c_FRAME_MARKER_2
        ST_MARKER_3,          --! Escribiendo marcador byte 3: c_FRAME_MARKER_3
        ST_WAIT_LINE,         --! Esperando inicio de línea (lvalid_i='1') o fin de frame
        ST_CAPTURE,           --! Capturando píxeles Y de la línea activa
        ST_LINE_END,          --! Línea completada; incrementar s_row_cnt
        ST_FRAME_END          --! Frame completado; emitir frame_done_o
    );

    signal s_state : t_cap_state := ST_IDLE;  --! Estado actual de la FSM de captura

    signal s_byte_cnt : unsigned(10 downto 0)        := (others => '0');  --! Contador de bytes recibidos en la línea (par=Y, impar=croma)
    signal s_col_cnt  : integer range 0 to g_H_RES-1 := 0;               --! Columna actual dentro de la línea
    signal s_row_cnt  : integer range 0 to g_V_RES-1 := 0;               --! Fila actual dentro del frame

    signal overflow_r   : std_logic := '0';  --! Registro de overflow; se mantiene hasta el siguiente ST_IDLE
    signal frame_done_r : std_logic := '0';  --! Registro de frame_done; pulso de 1 ciclo

    signal rst_pixclk_2ff: std_logic_vector(1 downto 0) :=(others => '1');
    signal rst_pixclk : std_logic;

begin

    frame_done_o <= frame_done_r;
    overflow_o   <= overflow_r;

    p_reset_sync: process(pixclk_i, reset_i)
    begin
        if reset_i = '1' then
            rst_pixclk_2ff <= (others => '1');
        elsif rising_edge(pixclk_i) then
            rst_pixclk_2ff(0) <= '0';
            rst_pixclk_2ff(1) <= rst_pixclk_2ff(0);
        end if;
    end process p_reset_sync;
    rst_pixclk <= rst_pixclk_2ff(1);


    --! \brief FSM de captura de frame — dominio pixclk_i
    p_capture : process(pixclk_i)
    begin
        -- /todo Reset aquí no se cumple porque pixclk_i es una señal post-reset 
        if rising_edge(pixclk_i) then
            if rst_pixclk = '1' then
                s_state      <= ST_IDLE;
                s_byte_cnt   <= (others => '0');
                s_col_cnt    <= 0;
                s_row_cnt    <= 0;
                fifo_data_o  <= (others => '0');
                fifo_wr_o    <= '0';
                overflow_r   <= '0';
                frame_done_r <= '0';
            else
                fifo_wr_o    <= '0';
                frame_done_r <= '0';

                case s_state is

                    when ST_IDLE =>
                        s_byte_cnt <= (others => '0');
                        s_col_cnt  <= 0;
                        s_row_cnt  <= 0;
                        overflow_r <= '0';
                        if capture_en_i = '1' then
                            if fvalid_i = '0' then
                                s_state <= ST_WAIT_FRAME_START;
                            end if;
                        end if;

                    when ST_WAIT_FRAME_START =>
                        if capture_en_i = '0' then
                            s_state <= ST_IDLE;
                        elsif fvalid_i = '1' then
                            s_state <= ST_MARKER_0;
                        end if;

                    -----------------------------------------------------------
                    -- Marcador de inicio de frame
                    -----------------------------------------------------------
                    when ST_MARKER_0 =>
                        if fifo_full_i = '0' then
                            fifo_data_o <= c_FRAME_MARKER_0;
                            fifo_wr_o   <= '1';
                            s_state     <= ST_MARKER_1;
                        end if;

                    when ST_MARKER_1 =>
                        if fifo_full_i = '0' then
                            fifo_data_o <= c_FRAME_MARKER_1;
                            fifo_wr_o   <= '1';
                            s_state     <= ST_MARKER_2;
                        end if;

                    when ST_MARKER_2 =>
                        if fifo_full_i = '0' then
                            fifo_data_o <= c_FRAME_MARKER_2;
                            fifo_wr_o   <= '1';
                            s_state     <= ST_MARKER_3;
                        end if;

                    when ST_MARKER_3 =>
                        if fifo_full_i = '0' then
                            fifo_data_o <= c_FRAME_MARKER_3;
                            fifo_wr_o   <= '1';
                            s_state     <= ST_WAIT_LINE;
                        end if;

                    when ST_WAIT_LINE =>
                        s_byte_cnt <= (others => '0');
                        s_col_cnt  <= 0;
                        if fvalid_i = '0' then
                            s_state <= ST_FRAME_END;
                        elsif lvalid_i = '1' then
                            s_state <= ST_CAPTURE;
                        end if;

                    -----------------------------------------------------------
                    -- Captura con sustituciones para evitar falsos positivos
                    -- s_byte_cnt(0)='1' → byte Y (capturar)
                    -- s_byte_cnt(0)='0' → byte croma (descartar)
                    -----------------------------------------------------------
                    when ST_CAPTURE =>
                        if lvalid_i = '0' then
                            s_state <= ST_LINE_END;
                        else
                            s_byte_cnt <= s_byte_cnt + 1;

                            if s_byte_cnt(0) = '0' then
                                if fifo_full_i = '0' then
                                    if    data_i = c_PROTO_RESERVED_FF then fifo_data_o <= c_PROTO_REPLACE_FF;
                                    elsif data_i = c_PROTO_RESERVED_AA then fifo_data_o <= c_PROTO_REPLACE_AA;
                                    elsif data_i = c_PROTO_RESERVED_55 then fifo_data_o <= c_PROTO_REPLACE_55;
                                    else                                     fifo_data_o <= data_i;
                                    end if;
                                    fifo_wr_o <= '1';
                                else
                                    overflow_r <= '1';
                                end if;

                                if s_col_cnt = g_H_RES - 1 then
                                    s_col_cnt <= 0;
                                else
                                    s_col_cnt <= s_col_cnt + 1;
                                end if;
                            end if;
                        end if;

                    when ST_LINE_END =>
                        s_byte_cnt <= (others => '0');
                        s_col_cnt  <= 0;
                        if s_row_cnt = g_V_RES - 1 then
                            s_row_cnt <= 0;
                        else
                            s_row_cnt <= s_row_cnt + 1;
                        end if;
                        if fvalid_i = '0' then
                            s_state <= ST_FRAME_END;
                        else
                            s_state <= ST_WAIT_LINE;
                        end if;

                    when ST_FRAME_END =>
                        frame_done_r <= '1';
                        s_state      <= ST_IDLE;

                    when others =>
                        s_state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_capture;

end architecture rtl;
