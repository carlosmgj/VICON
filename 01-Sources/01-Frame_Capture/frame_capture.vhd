--! \file frame_capture.vhd
--! \brief Capturador de frames para el sensor MT9V111.
--!
--! Marcador de inicio de frame (4 bytes sin solapamiento interno):
--!   0xFF 0x00 0xAA 0x55
--!
--! Los píxeles con valor 0xFF se sustituyen por 0xFE y los 0x00 por 0x01
--! para garantizar que el marcador no aparece en los datos de imagen.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity frame_capture is
    generic (
        H_RES      : integer := 640;
        V_RES      : integer := 480;
        FIFO_DEPTH : integer := 2048
    );
    port (
        pixclk      : in  std_logic;
        reset       : in  std_logic;
        frame_valid : in  std_logic;
        line_valid  : in  std_logic;
        dout        : in  std_logic_vector(7 downto 0);
        capture_en  : in  std_logic;
        fifo_data   : out std_logic_vector(7 downto 0);
        fifo_wr     : out std_logic;
        fifo_full   : in  std_logic;
        frame_done  : out std_logic;
        overflow    : out std_logic
    );
end entity frame_capture;

architecture rtl of frame_capture is

    type cap_state_t is (
        ST_IDLE,
        ST_WAIT_FRAME_START,
        ST_MARKER_0,   --! 0xFF
        ST_MARKER_1,   --! 0x00
        ST_MARKER_2,   --! 0xAA
        ST_MARKER_3,   --! 0x55
        ST_WAIT_LINE,
        ST_CAPTURE,
        ST_FRAME_END
    );
    signal state : cap_state_t := ST_IDLE;

    signal byte_sel     : std_logic := '0';
    signal col_cnt      : integer range 0 to H_RES - 1 := 0;
    signal row_cnt      : integer range 0 to V_RES - 1 := 0;
    signal overflow_r   : std_logic := '0';
    signal frame_done_r : std_logic := '0';

    attribute mark_debug : string;
    attribute mark_debug of state       : signal is "true";
    attribute mark_debug of byte_sel    : signal is "true";
    attribute mark_debug of col_cnt     : signal is "true";
    attribute mark_debug of row_cnt     : signal is "true";
    attribute mark_debug of fifo_wr     : signal is "true";
    attribute mark_debug of overflow_r  : signal is "true";

begin

    frame_done <= frame_done_r;
    overflow   <= overflow_r;

    p_capture : process(pixclk)
    begin
        if rising_edge(pixclk) then
            if reset = '1' then
                state        <= ST_IDLE;
                byte_sel     <= '0';
                col_cnt      <= 0;
                row_cnt      <= 0;
                fifo_data    <= (others => '0');
                fifo_wr      <= '0';
                overflow_r   <= '0';
                frame_done_r <= '0';
            else
                fifo_wr      <= '0';
                frame_done_r <= '0';

                case state is

                    when ST_IDLE =>
                        byte_sel   <= '0';
                        col_cnt    <= 0;
                        row_cnt    <= 0;
                        overflow_r <= '0';
                        if capture_en = '1' then
                            if frame_valid = '0' then
                                state <= ST_WAIT_FRAME_START;
                            end if;
                        end if;

                    when ST_WAIT_FRAME_START =>
                        if capture_en = '0' then
                            state <= ST_IDLE;
                        elsif frame_valid = '1' then
                            state <= ST_MARKER_0;
                        end if;

                    when ST_MARKER_0 =>
                        if fifo_full = '0' then
                            fifo_data <= x"FF";
                            fifo_wr   <= '1';
                            state     <= ST_MARKER_1;
                        end if;

                    when ST_MARKER_1 =>
                        if fifo_full = '0' then
                            fifo_data <= x"00";
                            fifo_wr   <= '1';
                            state     <= ST_MARKER_2;
                        end if;

                    when ST_MARKER_2 =>
                        if fifo_full = '0' then
                            fifo_data <= x"AA";
                            fifo_wr   <= '1';
                            state     <= ST_MARKER_3;
                        end if;

                    when ST_MARKER_3 =>
                        if fifo_full = '0' then
                            fifo_data <= x"55";
                            fifo_wr   <= '1';
                            state     <= ST_WAIT_LINE;
                        end if;

                    when ST_WAIT_LINE =>
                        byte_sel <= '0';
                        col_cnt  <= 0;
                        if frame_valid = '0' then
                            state <= ST_FRAME_END;
                        elsif line_valid = '1' then
                            state <= ST_CAPTURE;
                        end if;

                    when ST_CAPTURE =>
                        byte_sel <= not byte_sel;

                        if byte_sel = '0' then
                            if fifo_full = '0' then
                                if dout = x"FF" then
                                    fifo_data <= x"FE";
                                elsif dout = x"00" then
                                    fifo_data <= x"01";
                                else
                                    fifo_data <= dout;
                                end if;
                                fifo_wr <= '1';
                            else
                                overflow_r <= '1';
                            end if;

                            if col_cnt = H_RES - 1 then
                                col_cnt <= 0;
                            else
                                col_cnt <= col_cnt + 1;
                            end if;
                        end if;

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

                    when ST_FRAME_END =>
                        frame_done_r <= '1';
                        state        <= ST_IDLE;

                    when others =>
                        state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_capture;

end architecture rtl;
