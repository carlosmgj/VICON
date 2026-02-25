library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity testbench is
end testbench;

architecture Structural of testbench is
    -- 1. SEÑALES DE INFRAESTRUCTURA
    signal clk_base  : std_logic;
    signal rst_raw   : std_logic;
    signal mclk      : std_logic;
    signal locked    : std_logic;
    signal rst_final : std_logic;

    -- 2. SEÑALES DEL BUS I2C (Solo para I2C!)
    signal sclk_bus  : std_logic;
    signal sda_bus   : std_logic := 'H'; -- Pull-up virtual
    signal done_sig  : std_logic;

begin

    -- Generador inicial de señales (basado en tu tb_dut.vhd)
    u_reloj : entity work.clk_reset_gen
        port map (
            clk_out   => clk_base,  -- Reloj de 100MHz para el MMCM
            reset_out => rst_raw    -- Reset inicial
        );

    -- MMCM (Si quieres usarlo para generar el reloj del sistema)
    mi_MMCM : entity work.clk_wiz_0
        port map (
            clk_in1  => clk_base,
            reset    => rst_raw,
            clk_out1 => mclk,
            locked   => locked
        );

    -- Lógica de Reset: El sistema solo sale de reset cuando el reloj es estable
    rst_final <= rst_raw or (not locked);

    -- Instancia del DUT (El Maestro I2C)
    u_dut : entity work.TOP
        generic map ( SENSOR_ADDR => "1011100" )
        port map (
            clk   => mclk,       -- Usa el reloj del MMCM
            reset => rst_final,  -- Reset sincronizado
            sclk  => sclk_bus,   -- Genera el reloj I2C
            sdata => sda_bus,    -- Datos I2C
            done  => done_sig
        );

    -- Instancia del Agente (El Esclavo I2C)
    u_sensor : entity work.mt9v111_agent
        generic map ( I2C_ADDR => "1011100" )
        port map (
            scl   => sclk_bus,   -- Escucha el reloj del DUT
            sda   => sda_bus,    -- Escucha/Habla en el bus
            pixclk => open, fval => open, lval => open, dout => open
        );

end Structural;
