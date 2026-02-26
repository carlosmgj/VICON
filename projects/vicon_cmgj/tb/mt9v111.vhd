--! \file mt9v111.vhd
--! Archivo fuente VHDL para el agente de simulaci贸n del sensor MT9V111.
--! \page AGENTE MT9V111
--! \section Descripcion
--! Este m贸dulo simula el comportamiento b谩sico del sensor de imagen MT9V111, generando un patr贸n de video y monitoreando la interfaz I2C para detectar configuraciones.
--! \section Uso
--! El agente se puede instanciar en un banco de pruebas (testbench) para verificar la integraci贸n del sensor con otros componentes, como un decodificador de display.
--! \section author Author
--! Carlos Manuel Gomez Jimenez, DNI: 76037985P
--! \section PINOUT MT9V111 Sensor
--! \subsection CLOCKS_RESETS Relojes y Control de Sistema
--! - CLKIN: (Input) Reloj maestro de entrada al sensor. Por defecto 12 MHz (M谩x. 27 MHz).
--! - RESET#: (Input) Reset as铆ncrono del sensor (Activo nivel BAJO).
--! - STANDBY: (Input) Modo de ultra-bajo consumo (Activo nivel ALTO).
--! - OE#: (Input) Output Enable Bar. En ALTO pone en tri-estado todas las salidas excepto SDATA.
--! - SCAN_EN: (Input) Pin de test de f谩brica (Conectar a DGND).
--! - ADC_TEST: (Input) Pin de uso de f谩brica (Conectar a VAAPIX).
--! \subsection SERIAL_IF Interfaz de Control Serial (I2C/SCCB)
--! - SCLK: (Input) Reloj serie (Serial Clock).
--! - SDATA: (I/O) Datos serie bidireccionales (Serial Data).
--! - SADDR: (Input) Selecci贸n de direcci贸n I2C: Reg 0xB8 en ALTO (defecto), Reg 0x90 en BAJO.
--! \subsection VIDEO_OUT Interfaz de Salida de Video
--! - PIXCLK: (Output) Reloj de pixel. Los datos son v谩lidos en el flanco de subida. Frecuencia = Master Clock.
--! - LINE_VALID: (Output) Indica l铆nea activa (Activo nivel ALTO) durante la transmisi贸n de p铆xeles.
--! - FRAME_VALID: (Output) Indica cuadro activo (Activo nivel ALTO).
--! - DOUT[7:0]: (Output) Bus de datos de pixel (ITU-R BT.656/RGB). DOUT7 es el MSB y DOUT0 el LSB.
--! - FLASH: (Output) Estroboscopio para control de Flash (Flash Strobe).
--! \subsection POWER Alimentaci贸n y Referencias
--! - VDD: (Supply) Alimentaci贸n Digital (2.8V).
--! - VAA: (Supply) Alimentaci贸n Anal贸gica (2.8V).
--! - VAAPIX: (Supply) Alimentaci贸n del Pixel Array (2.8V).
--! - DGND: (Supply) Tierra Digital (Digital Ground).
--! - AGND: (Supply) Tierra Anal贸gica (Analog Ground).
--! - NC: Sin conexi贸n (No connect).



--! \file mt9v111.vhd
--! Archivo fuente VHDL para el agente de simulaci贸n del sensor MT9V111.
--! Modificado para responder activamente a tramas I2C.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sim_utils_pkg.all; -- 

entity mt9v111_agent is
    generic (
        -- Ajustado a 0x5C para coincidir con el SENSOR_ADDR del DUT 
        I2C_ADDR     : std_logic_vector(6 downto 0) := "1011100"; 
        IMG_WIDTH    : integer := 640; -- 
        IMG_HEIGHT   : integer := 480  -- 
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
    -- Se帽ales internas de control de video 
    signal clk_int : std_logic := '0';
    constant PIX_PERIOD : time := 37 ns; -- ~27MHz
    signal addr_rx : std_logic_vector(7 downto 0); 
    
    type reg_map_t is array (0 to 255) of std_logic_vector(15 downto 0);
    
    signal regs_core : reg_map_t := (
        16#00# => x"823A", -- Chip Version (ID real del MT9V111)
        16#0D# => x"0008", -- Reset/Misc Control (valor por defecto)
        others => x"CACA"
    );

    signal regs_ifp : reg_map_t := (
        16#01# => x"0001", -- Color Pipeline Control
        others => x"0FE0"
    );

begin

    -- Generador de Pixel Clock independiente 
    clk_int <= not clk_int after PIX_PERIOD/2;

    -----------------------------------------------------------
    -- PROCESO 2: Respondedor I2C Activo (Slave)
    -----------------------------------------------------------
    i2c_active_respond: process
        variable v_reg_addr : integer range 0 to 255;
        variable v_data_16  : std_logic_vector(15 downto 0);
        variable v_addr_dev : std_logic_vector(7 downto 0);
        variable write_n_read : std_logic;
    begin
        sda <= 'Z';
    
        -- 1. START
        wait until falling_edge(sda) and scl = '1';
        
        -- 2. Recibir Direcci髇 Dispositivo (8 bits)
        for i in 7 downto 0 loop
            wait until rising_edge(scl);
            v_addr_dev(i) := sda;
        end loop;
    
        if v_addr_dev(7 downto 1) = I2C_ADDR then
            -- ACK 1 (Direcci髇 Dispositivo)
            wait until falling_edge(scl);
            sda <= '0';
            wait until falling_edge(scl);
            sda <= 'Z';
            write_n_read := v_addr_dev(0);
                        
            if (write_n_read = '0') then
                log_to_file("reporte_final_1.txt", "COMANDO DE ESCRITURA", false);
            else
                log_to_file("reporte_final_1.txt", "COMANDO DE LECTURA", false);
            end if;
                        
            
            -- 3. Recibir Direcci髇 de Registro (8 bits)
            for i in 7 downto 0 loop
                wait until rising_edge(scl);
                v_data_16(i+8) := sda; -- Usamos v_data_16 temporalmente para ahorrar variables
            end loop;
            v_reg_addr := to_integer(unsigned(v_data_16(15 downto 8)));
           
            
            -- ACK 2 (Direcci髇 Registro)
            wait until falling_edge(scl);
            sda <= '0';
            wait until falling_edge(scl);
            sda <= 'Z';
    
            -- 4. Recibir Dato BYTE ALTO (8 bits)
            for i in 7 downto 0 loop
                wait until rising_edge(scl);
                v_data_16(i+8) := sda;
            end loop;
            
            -- ACK 3 (Byte Alto)
            wait until falling_edge(scl);
            sda <= '0';
            wait until falling_edge(scl);
            sda <= 'Z';
    
            -- 5. Recibir Dato BYTE BAJO (8 bits)
            for i in 7 downto 0 loop
                wait until rising_edge(scl);
                v_data_16(i) := sda;
            end loop;
            
            -- ACK 4 (Byte Bajo)
            wait until falling_edge(scl);
            sda <= '0';
            wait until falling_edge(scl);
            sda <= 'Z';
    
            -- 6. GUARDAR EN EL MAPA (Suponiendo que estamos en la p醙ina 0)
            regs_core(v_reg_addr) <= v_data_16;
            log_to_file("reporte_final_1.txt", "I2C Agente: Registro 0x" & 
            int_to_hex_str(v_reg_addr, 2) & " escrito con valor 0x" & int_to_hex_str(to_integer(unsigned(v_data_16)),4), false);
    
        end if;
    
        -- 7. STOP
        wait until rising_edge(sda) and scl = '1';
        log_to_file("reporte_final_1.txt", "I2C Agente: STOP detectado", false);
    end process;

end Behavioral;