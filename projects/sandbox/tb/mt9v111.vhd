--! \file mt9v111.vhd
--! Archivo fuente VHDL para el agente de simulación del sensor MT9V111.
--! \page AGENTE MT9V111
--! \section Descripcion
--! Este módulo simula el comportamiento básico del sensor de imagen MT9V111, generando un patrón de video y monitoreando la interfaz I2C para detectar configuraciones.
--! \section Uso
--! El agente se puede instanciar en un banco de pruebas (testbench) para verificar la integración del sensor con otros componentes, como un decodificador de display.
--! \section author Author
--! Carlos Manuel Gomez Jimenez, DNI: 76037985P
--! \section PINOUT MT9V111 Sensor
--! \subsection CLOCKS_RESETS Relojes y Control de Sistema
--! - CLKIN: (Input) Reloj maestro de entrada al sensor. Por defecto 12 MHz (Máx. 27 MHz).
--! - RESET#: (Input) Reset asíncrono del sensor (Activo nivel BAJO).
--! - STANDBY: (Input) Modo de ultra-bajo consumo (Activo nivel ALTO).
--! - OE#: (Input) Output Enable Bar. En ALTO pone en tri-estado todas las salidas excepto SDATA.
--! - SCAN_EN: (Input) Pin de test de fábrica (Conectar a DGND).
--! - ADC_TEST: (Input) Pin de uso de fábrica (Conectar a VAAPIX).
--! \subsection SERIAL_IF Interfaz de Control Serial (I2C/SCCB)
--! - SCLK: (Input) Reloj serie (Serial Clock).
--! - SDATA: (I/O) Datos serie bidireccionales (Serial Data).
--! - SADDR: (Input) Selección de dirección I2C: Reg 0xB8 en ALTO (defecto), Reg 0x90 en BAJO.
--! \subsection VIDEO_OUT Interfaz de Salida de Video
--! - PIXCLK: (Output) Reloj de pixel. Los datos son válidos en el flanco de subida. Frecuencia = Master Clock.
--! - LINE_VALID: (Output) Indica línea activa (Activo nivel ALTO) durante la transmisión de píxeles.
--! - FRAME_VALID: (Output) Indica cuadro activo (Activo nivel ALTO).
--! - DOUT[7:0]: (Output) Bus de datos de pixel (ITU-R BT.656/RGB). DOUT7 es el MSB y DOUT0 el LSB.
--! - FLASH: (Output) Estroboscopio para control de Flash (Flash Strobe).
--! \subsection POWER Alimentación y Referencias
--! - VDD: (Supply) Alimentación Digital (2.8V).
--! - VAA: (Supply) Alimentación Analógica (2.8V).
--! - VAAPIX: (Supply) Alimentación del Pixel Array (2.8V).
--! - DGND: (Supply) Tierra Digital (Digital Ground).
--! - AGND: (Supply) Tierra Analógica (Analog Ground).
--! - NC: Sin conexión (No connect).



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use work.sim_utils_pkg.all; -- Para usar log_to_file

entity mt9v111_agent is
    generic (
        I2C_ADDR : std_logic_vector(6 downto 0) := "1011100" -- 0x5C
    );
    port (
        clk      : in    std_logic; -- Reloj de sistema para muestreo
        reset    : in    std_logic;
        sclk     : in    std_logic;
        sdata    : in    std_logic;
        -- Salidas de estado para debug en hardware
        busy     : out   std_logic;
        match    : out   std_logic
    );
end mt9v111_agent;

architecture Behavioral of mt9v111_agent is
    -- Estados de la FSM
    type state_t is (IDLE, ADDR_BITS, ACK_BIT, STOP_DETECT);
    signal state : state_t := IDLE;

    -- Sincronizadores para señales asíncronas
    signal sclk_sync  : std_logic_vector(2 downto 0);
    signal sdata_sync : std_logic_vector(2 downto 0);
    
    -- Registro de desplazamiento para dirección
    signal shift_reg : std_logic_vector(7 downto 0);
    signal bit_cnt   : integer range 0 to 7 := 7;

begin

    --! \section SYNC Sincronización de señales de entrada
    process(clk)
    begin
        if rising_edge(clk) then
            sclk_sync  <= sclk_sync(1 downto 0) & sclk;
            sdata_sync <= sdata_sync(1 downto 0) & sdata;
        end if;
    end process;
    
    process(clk)
        variable start_cond : boolean;
        variable stop_cond  : boolean;
        variable sclk_rise  : boolean;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state   <= IDLE;
                match   <= '0';
                busy    <= '0';
                bit_cnt <= 7;
            else
                -- Detectores de flancos
                start_cond := (sdata_sync(2) = '1' and sdata_sync(1) = '0' and sclk_sync(1) = '1');
                stop_cond  := (sdata_sync(2) = '0' and sdata_sync(1) = '1' and sclk_sync(1) = '1');
                sclk_rise  := (sclk_sync(2) = '0' and sclk_sync(1) = '1');

                if start_cond then
                    state   <= ADDR_BITS;
                    bit_cnt <= 7;
                    busy    <= '1';
                elsif stop_cond then
                    state   <= IDLE;
                    busy    <= '0';
                else
                    case state is
                        when ADDR_BITS =>
                            if sclk_rise then
                                shift_reg(bit_cnt) <= sdata_sync(1);
                                if bit_cnt = 0 then
                                    state <= ACK_BIT;
                                else
                                    bit_cnt <= bit_cnt - 1;
                                end if;
                            end if;

                        when ACK_BIT =>
                            if sclk_rise then
                                -- Verificamos dirección (7 bits)
                                if shift_reg(7 downto 1) = I2C_ADDR then
                                    match <= '1';
                                    -- PRÁCTICA SIMULACIÓN: Imprimimos resultado
                                    if shift_reg(0) = '0' then
                                        log_to_file("reporte_final_1.txt", "SINTETIZABLE: Escritura detectada en 0x" & vec_to_str(I2C_ADDR), false);
                                    else
                                        log_to_file("reporte_final_1.txt", "SINTETIZABLE: Lectura detectada en 0x" & vec_to_str(I2C_ADDR), false);
                                    end if;
                                else
                                    match <= '0';
                                end if;
                                state <= IDLE; -- Volvemos a esperar otra trama
                            end if;
                            
                        when others => state <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;

end Behavioral;