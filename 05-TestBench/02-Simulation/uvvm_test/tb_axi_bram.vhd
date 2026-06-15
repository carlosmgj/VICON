library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axilite;
context bitvis_vip_axilite.vvc_context;

entity tb_axi_bram_dual_aspect is
end entity tb_axi_bram_dual_aspect;

architecture sim of tb_axi_bram_dual_aspect is

    constant C_SCOPE         : string := "TB AXI BRAM";
    constant C_ADDR_WIDTH     : natural := 12;
    constant C_DATA_WIDTH     : natural := 32;
    constant C_BRAM_BASE_ADDR : unsigned(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
    constant C_CLK_PERIOD     : time := 10 ns;

    signal clk     : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal axilite_if : t_axilite_if(write_address_channel(awaddr(C_ADDR_WIDTH - 1 downto 0)),
                                    write_data_channel(wdata(C_DATA_WIDTH - 1 downto 0),
                                                        wstrb((C_DATA_WIDTH / 8) - 1 downto 0)),
                                    read_address_channel(araddr(C_ADDR_WIDTH - 1 downto 0)),
                                    read_data_channel(rdata(C_DATA_WIDTH - 1 downto 0)));

    signal bram_en_a    : std_logic;
    signal bram_we_a    : std_logic_vector(3 downto 0);
    signal bram_addr_a  : std_logic_vector(11 downto 0);
    signal bram_wdata_a : std_logic_vector(31 downto 0);
    signal bram_rdata_a : std_logic_vector(31 downto 0);

    signal bram_en_b    : std_logic := '0';
    signal bram_addr_b  : std_logic_vector(14 downto 0) := (others => '0');
    signal bram_rdata_b : std_logic_vector(0 downto 0);

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

    i_axi_bram_ctrl : entity work.axi_bram_ctrl_0
        port map (
            s_axi_aclk    => clk,
            s_axi_aresetn => aresetn,

            s_axi_awaddr  => axilite_if.write_address_channel.awaddr,
            s_axi_awvalid => axilite_if.write_address_channel.awvalid,
            s_axi_awready => axilite_if.write_address_channel.awready,
            s_axi_awlen   => (others => '0'),
            s_axi_awsize  => "010",
            s_axi_awburst => "01",
            s_axi_awlock  => '0',
            s_axi_awcache => (others => '0'),
            s_axi_awprot  => axilite_if.write_address_channel.awprot,

            s_axi_wdata   => axilite_if.write_data_channel.wdata,
            s_axi_wstrb   => axilite_if.write_data_channel.wstrb,
            s_axi_wvalid  => axilite_if.write_data_channel.wvalid,
            s_axi_wready  => axilite_if.write_data_channel.wready,
            s_axi_wlast   => '1',

            s_axi_bresp   => axilite_if.write_response_channel.bresp,
            s_axi_bvalid  => axilite_if.write_response_channel.bvalid,
            s_axi_bready  => axilite_if.write_response_channel.bready,

            s_axi_araddr  => axilite_if.read_address_channel.araddr,
            s_axi_arvalid => axilite_if.read_address_channel.arvalid,
            s_axi_arready => axilite_if.read_address_channel.arready,
            s_axi_arlen   => (others => '0'),
            s_axi_arsize  => "010",
            s_axi_arburst => "01",
            s_axi_arlock  => '0',
            s_axi_arcache => (others => '0'),
            s_axi_arprot  => axilite_if.read_address_channel.arprot,

            s_axi_rdata   => axilite_if.read_data_channel.rdata,
            s_axi_rresp   => axilite_if.read_data_channel.rresp,
            s_axi_rvalid  => axilite_if.read_data_channel.rvalid,
            s_axi_rready  => axilite_if.read_data_channel.rready,

            bram_rst_a    => open,
            bram_clk_a    => open,
            bram_en_a     => bram_en_a,
            bram_we_a     => bram_we_a,
            bram_addr_a   => bram_addr_a,
            bram_wrdata_a => bram_wdata_a,
            bram_rddata_a => bram_rdata_a
        );

    i_true_dual_port_bram : entity work.blk_mem_gen_0
        port map (
            clka  => clk,
            ena   => bram_en_a,
            wea   => (0 => or_reduce(bram_we_a)),
            addra => bram_addr_a(11 downto 2),
            dina  => bram_wdata_a,
            douta => bram_rdata_a,

            clkb  => clk,
            enb   => bram_en_b,
            web   => (others => '0'),
            addrb => bram_addr_b,
            dinb  => (others => '0'),
            doutb => bram_rdata_b
        );

    p_sequencer : process
    begin

        set_log_file_name("sim_log.txt");
        set_alert_file_name("sim_log.txt");

        log(ID_LOG_HDR, "Iniciando Simulacion: Sistema Mixto AXI (32 bits) a BRAM (1 bit)", C_SCOPE);

        aresetn <= '0';
        wait for C_CLK_PERIOD * 5;
        aresetn <= '1';
        wait until rising_edge(clk);

        -- =========================================================================
        -- PASO 0: Verificar precarga inicial de la BRAM via AXI (.coe: addr = valor)
        -- =========================================================================
        log(ID_SEQUENCER, "PASO 0: Verificando precarga inicial de la BRAM via AXI...", C_SCOPE);

        axilite_check(AXILITE_VVCT, 1, C_BRAM_BASE_ADDR + to_unsigned(0, C_ADDR_WIDTH),  x"0000_0000", "Precarga: word 0 = 0x00000000");
        axilite_check(AXILITE_VVCT, 1, C_BRAM_BASE_ADDR + to_unsigned(4, C_ADDR_WIDTH),  x"0000_0001", "Precarga: word 1 = 0x00000001");
        axilite_check(AXILITE_VVCT, 1, C_BRAM_BASE_ADDR + to_unsigned(8, C_ADDR_WIDTH),  x"0000_0002", "Precarga: word 2 = 0x00000002");
        axilite_check(AXILITE_VVCT, 1, C_BRAM_BASE_ADDR + to_unsigned(12, C_ADDR_WIDTH), x"0000_0003", "Precarga: word 3 = 0x00000003");

        await_completion(AXILITE_VVCT, 1, 20 us);

        -- =========================================================================
        -- PASO 1: Escritura de palabras de 32 bits via AXI
        -- =========================================================================
        log(ID_SEQUENCER, "PASO 1: Escribiendo palabras de 32 bits via AXI...", C_SCOPE);

        axilite_write(AXILITE_VVCT, 1,
                    C_BRAM_BASE_ADDR + to_unsigned(0, C_ADDR_WIDTH),
                    x"0000_0005", "Guardando el valor 5 en la primera palabra");

        axilite_write(AXILITE_VVCT, 1,
                    C_BRAM_BASE_ADDR + to_unsigned(4, C_ADDR_WIDTH),
                    x"0000_0002", "Guardando el valor 2 en la segunda palabra");

        await_completion(AXILITE_VVCT, 1, 20 us);

        -- =========================================================================
        -- PASO 2: Confirmacion de los valores escritos via AXI
        -- =========================================================================
        log(ID_SEQUENCER, "PASO 2: Confirmando que el bus AXI lee los valores correctos...", C_SCOPE);

        axilite_check(AXILITE_VVCT, 1, C_BRAM_BASE_ADDR + to_unsigned(0, C_ADDR_WIDTH), x"0000_0005", "Verificando dato 5 por bus");
        axilite_check(AXILITE_VVCT, 1, C_BRAM_BASE_ADDR + to_unsigned(4, C_ADDR_WIDTH), x"0000_0002", "Verificando dato 2 por bus");

        await_completion(AXILITE_VVCT, 1, 20 us);

        -- =========================================================================
        -- PASO 3: Lectura bit a bit desde el Puerto B (1 bit)
        -- =========================================================================
        log(ID_SEQUENCER, "PASO 3: Iniciando la lectura bit a bit desde el Puerto B (1 bit)...", C_SCOPE);
        bram_en_b <= '1';

        bram_addr_b <= std_logic_vector(to_unsigned(0, 15));
        wait for C_CLK_PERIOD * 2;
        check_value(bram_rdata_b(0), '1', ERROR, "Verificacion Puerto B: Bit 0 debe ser '1'");

        bram_addr_b <= std_logic_vector(to_unsigned(1, 15));
        wait for C_CLK_PERIOD * 2;
        check_value(bram_rdata_b(0), '0', ERROR, "Verificacion Puerto B: Bit 1 debe ser '0'");

        bram_addr_b <= std_logic_vector(to_unsigned(2, 15));
        wait for C_CLK_PERIOD * 2;
        check_value(bram_rdata_b(0), '1', ERROR, "Verificacion Puerto B: Bit 2 debe ser '1'");

        bram_addr_b <= std_logic_vector(to_unsigned(32, 15));
        wait for C_CLK_PERIOD * 2;
        check_value(bram_rdata_b(0), '0', ERROR, "Segunda palabra - Bit 0 debe ser '0'");

        bram_addr_b <= std_logic_vector(to_unsigned(33, 15));
        wait for C_CLK_PERIOD * 2;
        check_value(bram_rdata_b(0), '1', ERROR, "Segunda palabra - Bit 1 debe ser '1'");

        bram_en_b <= '0';

        log(ID_LOG_HDR, "EJECUCION DE PRUEBAS COMPLETADA", C_SCOPE);
        report_alert_counters(FINAL);

        std.env.stop;
        wait;
    end process p_sequencer;

end architecture sim;