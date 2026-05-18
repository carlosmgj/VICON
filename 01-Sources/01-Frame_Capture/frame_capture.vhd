--! \file frame_capture.vhd
--! \brief Capturador de frames para el sensor MT9V111.
--!
--! Este módulo captura el canal de luminancia (Y) del stream YCbCr 4:2:2
--! que genera el MT9V111 y lo escribe en una FIFO asíncrona para su
--! transferencia al PC via FTDI.
--!
--! Formato YCbCr 4:2:2 del MT9V111 (orden por defecto):
--!   Byte 0: Cb   (croma, DESCARTAR)
--!   Byte 1: Y0   (luma,  CAPTURAR)
--!   Byte 2: Cr   (croma, DESCARTAR)
--!   Byte 3: Y1   (luma,  CAPTURAR)
--!   ...
--!
--! El módulo opera en el dominio de PIXCLK (salida de la cámara, ~25 MHz).
--! La FIFO de salida es asíncrona para permitir el cruce al dominio del FTDI.
--!
--! Señal capture_en:
--!   '1' permanente → streaming continuo
--!   '1' durante un frame → captura bajo demanda
--!   '0' → descarta todos los frames
--!
--! \note Solo se captura el canal Y (luminancia). La imagen resultante es
--!       en escala de grises, óptima para procesamiento con OpenCV.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity frame_capture is
    generic (
        H_RES      : integer := 640;   --! Resolución horizontal en píxeles
        V_RES      : integer := 480;   --! Resolución vertical en líneas
        FIFO_DEPTH : integer := 2048   --! Profundidad de la FIFO de salida (potencia de 2)
    );
    port (
        ---------------------------------------------------------------------------
        -- Dominio PIXCLK — cámara MT9V111
        ---------------------------------------------------------------------------
        pixclk      : in  std_logic;                     --! Reloj de píxel (~25 MHz)
        reset       : in  std_logic;                     --! Reset síncrono activo alto
        frame_valid : in  std_logic;                     --! FRAME_VALID de la cámara
        line_valid  : in  std_logic;                     --! LINE_VALID de la cámara
        dout        : in  std_logic_vector(7 downto 0);  --! Datos YCbCr de la cámara

        ---------------------------------------------------------------------------
        -- Control
        ---------------------------------------------------------------------------
        capture_en  : in  std_logic;   --! '1' = capturar frames, '0' = descartar

        ---------------------------------------------------------------------------
        -- Salida — FIFO asíncrona hacia dominio FTDI
        ---------------------------------------------------------------------------
        fifo_data   : out std_logic_vector(7 downto 0);  --! Byte Y a escribir en FIFO
        fifo_wr     : out std_logic;                     --! Pulso de escritura en FIFO
        fifo_full   : in  std_logic;                     --! FIFO llena (back-pressure)

        ---------------------------------------------------------------------------
        -- Estado
        ---------------------------------------------------------------------------
        frame_done  : out std_logic;   --! Pulso de 1 ciclo al completar un frame
        overflow    : out std_logic    --! '1' si se perdieron datos por FIFO llena
    );
end entity frame_capture;

architecture rtl of frame_capture is

    ---------------------------------------------------------------------------
    -- FSM del capturador
    ---------------------------------------------------------------------------
    type cap_state_t is (
        ST_IDLE,        --! Esperando frame_valid y capture_en
        ST_WAIT_LINE,   --! Dentro de frame, esperando line_valid
        ST_CAPTURE,     --! Capturando bytes de la línea activa
        ST_FRAME_END    --! Frame completado, pulso frame_done
    );
    signal state : cap_state_t := ST_IDLE;

    ---------------------------------------------------------------------------
    -- Contador de bytes dentro de cada píxel YCbCr 4:2:2
    -- El MT9V111 emite 2 bytes por píxel: [Cb/Cr, Y]
    -- byte_sel = '0' → byte de croma (descartar)
    -- byte_sel = '1' → byte de luma Y (capturar)
    ---------------------------------------------------------------------------
    signal byte_sel    : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Contadores de posición (para debug y control de resolución)
    ---------------------------------------------------------------------------
    signal col_cnt     : integer range 0 to H_RES - 1 := 0;
    signal row_cnt     : integer range 0 to V_RES - 1 := 0;

    ---------------------------------------------------------------------------
    -- Señales internas
    ---------------------------------------------------------------------------
    signal overflow_r  : std_logic := '0';
    signal frame_done_r: std_logic := '0';

    ---------------------------------------------------------------------------
    -- ILA / Debug
    ---------------------------------------------------------------------------
    attribute mark_debug : string;
    attribute mark_debug of state      : signal is "true";
    attribute mark_debug of byte_sel   : signal is "true";
    attribute mark_debug of col_cnt    : signal is "true";
    attribute mark_debug of row_cnt    : signal is "true";
    attribute mark_debug of fifo_wr    : signal is "true";
    attribute mark_debug of overflow_r : signal is "true";

begin

    frame_done <= frame_done_r;
    overflow   <= overflow_r;

    ---------------------------------------------------------------------------
    -- FSM principal — dominio PIXCLK
    ---------------------------------------------------------------------------
    p_capture : process(pixclk)
    begin
        if rising_edge(pixclk) then
            if reset = '1' then
                state       <= ST_IDLE;
                byte_sel    <= '0';
                col_cnt     <= 0;
                row_cnt     <= 0;
                fifo_data   <= (others => '0');
                fifo_wr     <= '0';
                overflow_r  <= '0';
                frame_done_r<= '0';
            else
                -- Pulsos de un ciclo por defecto
                fifo_wr      <= '0';
                frame_done_r <= '0';

                case state is

                    -----------------------------------------------------------
                    -- Esperar frame_valid activo y capture_en habilitado
                    -----------------------------------------------------------
                    when ST_IDLE =>
                        byte_sel <= '0';
                        col_cnt  <= 0;
                        row_cnt  <= 0;
                        overflow_r <= '0';
                        if frame_valid = '1' and capture_en = '1' then
                            state <= ST_WAIT_LINE;
                        end if;

                    -----------------------------------------------------------
                    -- Dentro del frame, esperando line_valid
                    -----------------------------------------------------------
                    when ST_WAIT_LINE =>
                        byte_sel <= '0';
                        col_cnt  <= 0;
                        if frame_valid = '0' then
                            -- Frame terminado
                            state <= ST_FRAME_END;
                        elsif line_valid = '1' then
                            state <= ST_CAPTURE;
                        end if;

                    -----------------------------------------------------------
                    -- Capturando bytes de la línea activa
                    -- byte_sel='0' → croma (descartar)
                    -- byte_sel='1' → luma Y (escribir en FIFO)
                    -----------------------------------------------------------
                    when ST_CAPTURE =>
                        byte_sel <= not byte_sel;

                        if byte_sel = '1' then
                            -- Byte de luma Y — escribir en FIFO
                            if fifo_full = '0' then
                                fifo_data <= dout;
                                fifo_wr   <= '1';
                            else
                                -- FIFO llena — dato perdido
                                overflow_r <= '1';
                            end if;

                            -- Avanzar contador de columna
                            if col_cnt = H_RES - 1 then
                                col_cnt <= 0;
                            else
                                col_cnt <= col_cnt + 1;
                            end if;
                        end if;

                        -- Fin de línea
                        if line_valid = '0' then
                            byte_sel <= '0';
                            col_cnt  <= 0;
                            if row_cnt = V_RES - 1 then
                                row_cnt <= 0;
                            else
                                row_cnt <= row_cnt + 1;
                            end if;
                            state <= ST_WAIT_LINE;
                        end if;

                    -----------------------------------------------------------
                    -- Frame completado
                    -----------------------------------------------------------
                    when ST_FRAME_END =>
                        frame_done_r <= '1';
                        if capture_en = '1' then
                            state <= ST_IDLE;   --! Continuar capturando
                        else
                            state <= ST_IDLE;   --! capture_en='0' → quedarse en IDLE
                        end if;

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_capture;

end architecture rtl;
