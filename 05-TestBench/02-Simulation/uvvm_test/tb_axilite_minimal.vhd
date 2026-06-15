library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axilite;
context bitvis_vip_axilite.vvc_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

entity tb_axilite_minimal is
end entity tb_axilite_minimal;

architecture sim of tb_axilite_minimal is

    constant C_SCOPE      : string := "TB AXILITE MIN";
    constant C_ADDR_WIDTH : natural := 12;
    constant C_DATA_WIDTH : natural := 32;
    constant C_CLK_PERIOD : time := 10 ns;

    signal clk : std_logic := '0';

    signal axilite_if : t_axilite_if(write_address_channel(awaddr(C_ADDR_WIDTH - 1 downto 0)),
                                      write_data_channel(wdata(C_DATA_WIDTH - 1 downto 0),
                                                          wstrb((C_DATA_WIDTH / 8) - 1 downto 0)),
                                      read_address_channel(araddr(C_ADDR_WIDTH - 1 downto 0)),
                                      read_data_channel(rdata(C_DATA_WIDTH - 1 downto 0)));

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;


    clk <= not clk after C_CLK_PERIOD / 2;

    i_axilite_vvc : entity bitvis_vip_axilite.axilite_vvc
        generic map (
            GC_INSTANCE_IDX => 1,
            GC_ADDR_WIDTH   => C_ADDR_WIDTH,
            GC_DATA_WIDTH   => C_DATA_WIDTH
        )
        port map (
            clk                   => clk,
            axilite_vvc_master_if => axilite_if
        );

    -- =====================================================================
    -- Slave dummy combinacional/registrado: responde siempre OK
    -- bvalid/rvalid se mantienen estables en '0' cuando no hay transacción
    -- =====================================================================
    p_dummy_slave : process(clk)
    begin
        if rising_edge(clk) then
            -- Write Address Channel
            axilite_if.write_address_channel.awready <= axilite_if.write_address_channel.awvalid;

            -- Write Data Channel
            axilite_if.write_data_channel.wready <= axilite_if.write_data_channel.wvalid;

            -- Write Response Channel
            if axilite_if.write_data_channel.wvalid = '1' then
                axilite_if.write_response_channel.bvalid <= '1';
                axilite_if.write_response_channel.bresp  <= "00";
            else
                axilite_if.write_response_channel.bvalid <= '0';
            end if;

            -- Read Address Channel
            axilite_if.read_address_channel.arready <= axilite_if.read_address_channel.arvalid;

            -- Read Data Channel
            if axilite_if.read_address_channel.arvalid = '1' then
                axilite_if.read_data_channel.rvalid <= '1';
                axilite_if.read_data_channel.rdata  <= x"DEAD_BEEF";
                axilite_if.read_data_channel.rresp  <= "00";
            else
                axilite_if.read_data_channel.rvalid <= '0';
            end if;
        end if;
    end process p_dummy_slave;

    -- =====================================================================
    -- Sequencer
    -- =====================================================================
    p_sequencer : process
    begin
        log(ID_LOG_HDR, "Test minimo AXILITE VVC", C_SCOPE);

        wait for C_CLK_PERIOD * 5;

        axilite_write(AXILITE_VVCT, 1, to_unsigned(0, C_ADDR_WIDTH), x"0000_0005", "Write test");
        await_completion(AXILITE_VVCT, 1, 20 us);

        axilite_check(AXILITE_VVCT, 1, to_unsigned(0, C_ADDR_WIDTH), x"DEAD_BEEF", "Read check");
        await_completion(AXILITE_VVCT, 1, 20 us);

        log(ID_LOG_HDR, "FIN TEST", C_SCOPE);
        report_alert_counters(FINAL);
        std.env.stop;
        wait;
    end process p_sequencer;

end architecture sim;