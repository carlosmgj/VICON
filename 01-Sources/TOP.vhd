--! \file TOP.vhd
--! \brief Top-level del sistema de visión con la cámara MT9V111 y FTDI FT232H.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity TOP is
    generic (
        CLK_FREQ_HZ  : integer                       := 100_000_000;
        I2C_FREQ_HZ  : integer                       := 400_000;
        FIFO_DEPTH   : integer                       := 16;
        SENSOR_ADDR  : std_logic_vector(6 downto 0) := "1011100"
    );
    port (
        clk         : in    std_logic;
        SW          : in    std_logic_vector(15 downto 0);
        LED         : out   std_logic_vector(15 downto 0);
        CAT         : out   std_logic_vector(6 downto 0);
        DP          : out   std_logic;
        AN          : out   std_logic_vector(3 downto 0);
        BTN         : in    std_logic_vector(4 downto 0);
        dout        : in    std_logic_vector(7 downto 0);
        line_valid  : in    std_logic;
        pixclk      : in    std_logic;
        frame_valid : in    std_logic;
        cam_reset_n : out   std_logic;
        sclk        : inout std_logic;
        sdata       : inout std_logic;
        cam_mclk    : out   std_logic;
        ADBUS       : out   std_logic_vector(7 downto 0);  --! Solo salida — FPGA siempre conduce
        ACBUS       : inout std_logic_vector(7 downto 0)
    );
end entity TOP;

architecture Behavioral of TOP is

    constant RESET_HOLD_CYCLES : integer := CLK_FREQ_HZ / 1000;
    constant RESET_WAIT_CYCLES : integer := CLK_FREQ_HZ / 1000 * 150;
    constant MCLK_DIV          : integer := 2;
    constant CHIP_ID_EXPECTED  : std_logic_vector(15 downto 0) := x"823A";

    signal mclk      : std_logic;
    signal locked    : std_logic;
    signal rst_final : std_logic;

    signal mclk_div_cnt : integer range 0 to MCLK_DIV - 1 := 0;
    signal cam_mclk_r   : std_logic := '0';

    signal i2c_rw       : std_logic                      := '0';
    signal i2c_start    : std_logic                      := '0';
    signal i2c_num_regs : integer range 1 to FIFO_DEPTH := 1;
    signal i2c_addr_reg : std_logic_vector(7 downto 0)  := (others => '0');
    signal i2c_wr_push  : std_logic                      := '0';
    signal i2c_wr_data  : std_logic_vector(15 downto 0) := (others => '0');
    signal i2c_wr_full  : std_logic;
    signal i2c_wr_empty : std_logic;
    signal i2c_rd_pop   : std_logic                      := '0';
    signal i2c_rd_data  : std_logic_vector(15 downto 0);
    signal i2c_rd_full  : std_logic;
    signal i2c_rd_empty : std_logic;
    signal i2c_busy     : std_logic;
    signal i2c_done     : std_logic;
    signal i2c_error    : std_logic;
    signal scl_out_i    : std_logic;
    signal sda_out_i    : std_logic;
    signal sda_oe_i     : std_logic;
    signal sda_in_i     : std_logic;

    ---------------------------------------------------------------------------
    -- Señales FTDI
    ---------------------------------------------------------------------------
    signal ftdi_clk     : std_logic;  --! CLKOUT 60 MHz via BUFG — ACBUS[5]
    signal ftdi_txe_n   : std_logic;  --! TXE# — ACBUS[1]
    signal ftdi_wr_n    : std_logic;  --! WR#  — ACBUS[3]
    signal ftdi_adbus   : std_logic_vector(7 downto 0);
    signal ftdi_tx_active : std_logic;

    signal cap_fifo_data  : std_logic_vector(7 downto 0);
    signal cap_fifo_wr    : std_logic;
    signal cap_fifo_full  : std_logic;
    signal cap_fifo_empty : std_logic;
    signal cap_fifo_dout  : std_logic_vector(7 downto 0);
    signal cap_fifo_rd_en : std_logic;
    signal cap_frame_done : std_logic;
    signal cap_overflow   : std_logic;
    signal cap_en         : std_logic;

    type main_state_t is (
        ST_CAM_RESET_ASSERT,
        ST_CAM_RESET_WAIT,
        ST_PAGE_SEL_FILL,
        ST_PAGE_SEL_START,
        ST_PAGE_SEL_WAIT,
        ST_CHIPID_RD_START,
        ST_CHIPID_RD_WAIT,
        ST_CHIPID_RD_DRAIN,
        ST_FINISH,
        ST_ERROR
    );
    signal state : main_state_t := ST_CAM_RESET_ASSERT;

    signal init_cnt    : integer range 0 to RESET_WAIT_CYCLES := 0;
    signal fill_cnt    : integer range 0 to FIFO_DEPTH        := 0;
    signal cam_reset_r : std_logic := '0';
    signal chip_id     : std_logic_vector(15 downto 0) := (others => '0');

    signal debug_sclk   : std_logic;
    signal debug_sdata  : std_logic;
    signal debug_dout   : std_logic_vector(7 downto 0);
    signal debug_pixclk : std_logic;
    signal debug_fval   : std_logic;
    signal debug_lval   : std_logic;
    signal debug_txe_n  : std_logic;
    signal debug_wr_n   : std_logic;

    attribute mark_debug : string;
    attribute dont_touch : string;

    attribute mark_debug of i2c_start      : signal is "true";
    attribute mark_debug of i2c_busy       : signal is "true";
    attribute mark_debug of i2c_done       : signal is "true";
    attribute mark_debug of i2c_error      : signal is "true";
    attribute mark_debug of debug_sclk     : signal is "true";
    attribute mark_debug of debug_sdata    : signal is "true";
    attribute mark_debug of state          : signal is "true";
    attribute mark_debug of cam_reset_r    : signal is "true";
    attribute mark_debug of cam_mclk_r     : signal is "true";
    attribute mark_debug of debug_dout     : signal is "true";
    attribute mark_debug of debug_pixclk   : signal is "true";
    attribute mark_debug of debug_fval     : signal is "true";
    attribute mark_debug of debug_lval     : signal is "true";
    attribute mark_debug of chip_id        : signal is "true";
    attribute mark_debug of debug_txe_n    : signal is "true";
    attribute mark_debug of debug_wr_n     : signal is "true";
    attribute mark_debug of cap_fifo_wr    : signal is "true";
    attribute mark_debug of cap_fifo_full  : signal is "true";
    attribute mark_debug of cap_overflow   : signal is "true";
    attribute mark_debug of cap_frame_done : signal is "true";
    attribute mark_debug of ftdi_tx_active : signal is "true";

    attribute dont_touch of i2c_start      : signal is "true";
    attribute dont_touch of i2c_busy       : signal is "true";
    attribute dont_touch of i2c_done       : signal is "true";
    attribute dont_touch of i2c_error      : signal is "true";
    attribute dont_touch of debug_sclk     : signal is "true";
    attribute dont_touch of debug_sdata    : signal is "true";
    attribute dont_touch of state          : signal is "true";
    attribute dont_touch of cam_reset_r    : signal is "true";
    attribute dont_touch of cam_mclk_r     : signal is "true";
    attribute dont_touch of debug_dout     : signal is "true";
    attribute dont_touch of debug_pixclk   : signal is "true";
    attribute dont_touch of debug_fval     : signal is "true";
    attribute dont_touch of debug_lval     : signal is "true";
    attribute dont_touch of chip_id        : signal is "true";
    attribute dont_touch of debug_txe_n    : signal is "true";
    attribute dont_touch of debug_wr_n     : signal is "true";
    attribute dont_touch of cap_fifo_wr    : signal is "true";
    attribute dont_touch of cap_fifo_full  : signal is "true";
    attribute dont_touch of cap_overflow   : signal is "true";
    attribute dont_touch of cap_frame_done : signal is "true";
    attribute dont_touch of ftdi_tx_active : signal is "true";

begin

    sclk     <= '0' when scl_out_i = '0' else 'Z';
    sdata    <= sda_out_i when sda_oe_i = '1' else 'Z';
    sda_in_i <= sdata;

    cam_reset_n <= cam_reset_r;
    cam_mclk    <= cam_mclk_r;
    cap_en      <= '1' when state = ST_FINISH else '0';

    ---------------------------------------------------------------------------
    -- FTDI — CLKOUT via BUFG, OE# y PWRSAV# y SIWU# fijos
    ---------------------------------------------------------------------------
    ftdi_clk_buf : BUFG
        port map (
            I => ACBUS(5),
            O => ftdi_clk
        );

    ftdi_txe_n <= ACBUS(1);
    ACBUS(0)   <= 'Z';        --! RXF# — entrada
    ACBUS(1)   <= 'Z';        --! TXE# — entrada
    ACBUS(2)   <= '1';        --! RD# inactivo
    ACBUS(3)   <= ftdi_wr_n;  --! WR#
    ACBUS(4)   <= '1';        --! SIWU# — siempre alto
    -- ACBUS(5) CLKOUT — entrada via BUFG
    ACBUS(6)   <= '1';        --! OE# — siempre inactivo para escritura
    ACBUS(7)   <= '1';        --! PWRSAV# — siempre alto

    --! ADBUS — siempre conducido por la FPGA
    ADBUS <= ftdi_adbus;

    CAT <= (others => '0');
    DP  <= '0';
    AN  <= (others => '1');

    p_debug : process(mclk)
    begin
        if rising_edge(mclk) then
            debug_sclk   <= scl_out_i;
            debug_sdata  <= sda_in_i;
            debug_dout   <= dout;
            debug_pixclk <= pixclk;
            debug_fval   <= frame_valid;
            debug_lval   <= line_valid;
            debug_txe_n  <= ftdi_txe_n;
            debug_wr_n   <= ftdi_wr_n;
        end if;
    end process p_debug;

    p_cam_mclk : process(mclk)
    begin
        if rising_edge(mclk) then
            if rst_final = '1' then
                mclk_div_cnt <= 0;
                cam_mclk_r   <= '0';
            elsif mclk_div_cnt = MCLK_DIV - 1 then
                mclk_div_cnt <= 0;
                cam_mclk_r   <= not cam_mclk_r;
            else
                mclk_div_cnt <= mclk_div_cnt + 1;
            end if;
        end if;
    end process p_cam_mclk;

    mi_MMCM : entity work.clk_wiz_0
        port map (
            clk_in1  => clk,
            reset    => BTN(0),
            clk_out1 => mclk,
            locked   => locked
        );

    rst_final <= not locked;

    u_frame_capture : entity work.frame_capture
        generic map (
            H_RES      => 640,
            V_RES      => 480,
            FIFO_DEPTH => 4096
        )
        port map (
            pixclk      => pixclk,
            reset       => rst_final,
            frame_valid => frame_valid,
            line_valid  => line_valid,
            dout        => dout,
            capture_en  => cap_en,
            fifo_data   => cap_fifo_data,
            fifo_wr     => cap_fifo_wr,
            fifo_full   => cap_fifo_full,
            frame_done  => cap_frame_done,
            overflow    => cap_overflow
        );

    u_async_fifo : entity work.fifo_generator_0
        port map (
            wr_clk => pixclk,
            din    => cap_fifo_data,
            wr_en  => cap_fifo_wr,
            full   => cap_fifo_full,
            rd_clk => ftdi_clk,
            dout   => cap_fifo_dout,
            rd_en  => cap_fifo_rd_en,
            empty  => cap_fifo_empty,
            rst    => rst_final
        );

    u_ftdi_ctrl : entity work.ftdi_controller
        port map (
            ftdi_clk   => ftdi_clk,
            reset      => rst_final,
            fifo_dout  => cap_fifo_dout,
            fifo_empty => cap_fifo_empty,
            fifo_rd_en => cap_fifo_rd_en,
            ftdi_txe_n => ftdi_txe_n,
            ftdi_wr_n  => ftdi_wr_n,
            adbus_out  => ftdi_adbus,
            tx_active  => ftdi_tx_active
        );

    u_i2c : entity work.i2c_master
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            I2C_FREQ_HZ => I2C_FREQ_HZ,
            FIFO_DEPTH  => FIFO_DEPTH
        )
        port map (
            clk           => mclk,
            reset         => rst_final,
            rw            => i2c_rw,
            start_i2c     => i2c_start,
            num_regs      => i2c_num_regs,
            addr_dev      => SENSOR_ADDR,
            addr_reg      => i2c_addr_reg,
            wr_fifo_push  => i2c_wr_push,
            wr_fifo_data  => i2c_wr_data,
            wr_fifo_full  => i2c_wr_full,
            wr_fifo_empty => i2c_wr_empty,
            rd_fifo_pop   => i2c_rd_pop,
            rd_fifo_data  => i2c_rd_data,
            rd_fifo_full  => i2c_rd_full,
            rd_fifo_empty => i2c_rd_empty,
            busy          => i2c_busy,
            done          => i2c_done,
            error         => i2c_error,
            scl_out       => scl_out_i,
            sda_out       => sda_out_i,
            sda_oe_o      => sda_oe_i,
            sda_in        => sda_in_i
        );

    p_fsm : process(mclk)
    begin
        if rising_edge(mclk) then
            if rst_final = '1' then
                state        <= ST_CAM_RESET_ASSERT;
                cam_reset_r  <= '0';
                init_cnt     <= 0;
                i2c_rw       <= '0';
                i2c_start    <= '0';
                i2c_wr_push  <= '0';
                i2c_rd_pop   <= '0';
                i2c_num_regs <= 1;
                i2c_addr_reg <= (others => '0');
                i2c_wr_data  <= (others => '0');
                fill_cnt     <= 0;
                chip_id      <= (others => '0');
                LED(0)       <= '0';
                LED(1)       <= '0';
            else
                i2c_start   <= '0';
                i2c_wr_push <= '0';
                i2c_rd_pop  <= '0';

                case state is

                    when ST_CAM_RESET_ASSERT =>
                        cam_reset_r <= '0';
                        if init_cnt = RESET_HOLD_CYCLES - 1 then
                            init_cnt <= 0;
                            state    <= ST_CAM_RESET_WAIT;
                        else
                            init_cnt <= init_cnt + 1;
                        end if;

                    when ST_CAM_RESET_WAIT =>
                        cam_reset_r <= '1';
                        if init_cnt = RESET_WAIT_CYCLES - 1 then
                            init_cnt <= 0;
                            fill_cnt <= 0;
                            state    <= ST_PAGE_SEL_FILL;
                        else
                            init_cnt <= init_cnt + 1;
                        end if;

                    when ST_PAGE_SEL_FILL =>
                        if i2c_wr_full = '0' then
                            i2c_wr_data <= x"0004";
                            i2c_wr_push <= '1';
                            state       <= ST_PAGE_SEL_START;
                        end if;

                    when ST_PAGE_SEL_START =>
                        if i2c_busy = '0' then
                            i2c_rw       <= '0';
                            i2c_addr_reg <= x"01";
                            i2c_num_regs <= 1;
                            i2c_start    <= '1';
                            state        <= ST_PAGE_SEL_WAIT;
                        end if;

                    when ST_PAGE_SEL_WAIT =>
                        if i2c_error = '1' then
                            state <= ST_ERROR;
                        elsif i2c_done = '1' then
                            state <= ST_CHIPID_RD_START;
                        end if;

                    when ST_CHIPID_RD_START =>
                        if i2c_busy = '0' and i2c_rd_empty = '1' then
                            i2c_rw       <= '1';
                            i2c_addr_reg <= x"FF";
                            i2c_num_regs <= 1;
                            i2c_start    <= '1';
                            state        <= ST_CHIPID_RD_WAIT;
                        end if;

                    when ST_CHIPID_RD_WAIT =>
                        if i2c_error = '1' then
                            state <= ST_ERROR;
                        elsif i2c_done = '1' then
                            state <= ST_CHIPID_RD_DRAIN;
                        end if;

                    when ST_CHIPID_RD_DRAIN =>
                        if i2c_rd_empty = '0' then
                            i2c_rd_pop <= '1';
                            chip_id    <= i2c_rd_data;
                            if i2c_rd_data = CHIP_ID_EXPECTED then
                                state <= ST_FINISH;
                            else
                                state <= ST_ERROR;
                            end if;
                        end if;

                    when ST_FINISH =>
                        LED(0) <= '1';
                        LED(1) <= '0';
                        state  <= ST_FINISH;

                    when ST_ERROR =>
                        LED(0) <= '0';
                        LED(1) <= '1';
                        state  <= ST_ERROR;

                    when others =>
                        state <= ST_CAM_RESET_ASSERT;

                end case;
            end if;
        end if;
    end process p_fsm;

    LED(15 downto 2) <= SW(15 downto 2);

end architecture Behavioral;
