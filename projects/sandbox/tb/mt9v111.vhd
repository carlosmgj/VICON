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
use work.sim_utils_pkg.all;

entity mt9v111_agent is
    generic (
        I2C_ADDR     : std_logic_vector(6 downto 0) := "1011101"; -- 0xBA >> 1
        IMG_WIDTH    : integer := 640;
        IMG_HEIGHT   : integer := 480
    );
    port (
        -- Interfaz de Video (Paralela)
        pixclk  : out std_logic;
        fval    : out std_logic;
        lval    : out std_logic;
        dout    : out std_logic_vector(7 downto 0);
        
        -- Interfaz de Control (I2C/SCCB)
        scl     : in    std_logic;
        sda     : inout std_logic
    );
end mt9v111_agent;

architecture Behavioral of mt9v111_agent is
    -- Memoria de registros internos (emulación básica)
    type reg_array is array (0 to 255) of std_logic_vector(15 downto 0);
    signal regs : reg_array := (others => (others => '0'));
    
    -- Señales internas de control de video
    signal clk_int : std_logic := '0';
    constant PIX_PERIOD : time := 37 ns; -- ~27MHz
begin
    -- Generador de Pixel Clock independiente
    clk_int <= not clk_int after PIX_PERIOD/2;
    pixclk  <= clk_int;

    -----------------------------------------------------------
    -- PROCESO 1: Generador de Patrón de Video (Barras/Gradiente)
    -----------------------------------------------------------
    video_gen: process
        variable h_cnt : integer := 0;
        variable v_cnt : integer := 0;
    begin
        fval <= '0'; lval <= '0'; dout <= (others => '0');
        wait for 1 us; -- Pausa inicial antes del primer frame

        loop
            fval <= '1';
            for row in 0 to IMG_HEIGHT-1 loop
                lval <= '1';
                for col in 0 to IMG_WIDTH-1 loop
                    -- Generamos un gradiente simple
                    dout <= std_logic_vector(to_unsigned((col + row) mod 256, 8));
                    wait until falling_edge(clk_int);
                end loop;
                lval <= '0';
                wait for 10 * PIX_PERIOD; -- Blanking horizontal
            end loop;
            fval <= '0';
            wait for 100 * PIX_PERIOD; -- Blanking vertical (entre frames)
        end loop;
    end process;

    -----------------------------------------------------------
    -- PROCESO 2: Monitor I2C (Simplificado para simulación)
    -----------------------------------------------------------
    -- Este proceso "espía" las señales SCL/SDA y reporta al log
    i2c_spy: process
    begin
        wait until falling_edge(sda) and scl = '1'; -- Condición de START
        log_to_file("reporte_final_1.txt", "I2C Agente: START detectado", false);
        
        -- Aquí podrías añadir lógica para decodificar los bits,
        -- pero para empezar, con detectar actividad ya es un gran paso.
        
        wait until rising_edge(sda) and scl = '1'; -- Condición de STOP
        log_to_file("reporte_final_1.txt", "I2C Agente: STOP detectado", false);
    end process;

end Behavioral;