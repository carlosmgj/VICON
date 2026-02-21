--! \file TOP.vhd
--! Archivo fuente VHDL.
--! \mainpage Prueba de evaluacion Final 2
--! \image html diagram.svg "Diagrama lógico"
--! PROBLEMA 1
--! -  Cronómetro de DOS dígitos:
--!    -  El dígito de menor peso se incrementará cada décima de segundo.
--!    -  El dígito de mayor peso se incrementará cada segundo.
--! -  Funciona de manera ininterrumpida
--! -  Nuestro reloj de referencia (MCLK) es de 50MHz, pero Nuestro cronómetro ha de funcionar en tiempo real:
--!    -  Además de los DOS módulos que generan la cuenta (DOS contadores BCD)
--! necesitaremos de un temporizador en tiempo real (free-running).
--! PROBLEMA 2
--! -  DOS CONTADORES INDEPENDIENTES, distintos a los dos anteriores, habilitados MANUALMENTE
--!    -  ambos deben incrementar en paralelo su valor cada vez que actuamos MANUALMENTE sobre la señal de habilitación.
--!    -  El objetivo es visualizar los problemas inherentes a los actuadores electromecánicos e implementar su solución
--! \note El formato de comentario incluye ! para poder realizar documentacion dinamica con Doxygen. 
--! \section Uso
--! Acceder a la documentacion abriendo el archivo <b>index.html</b> dentro de la carpeta ./docs/html. <br>
--! En cada archivo (File), es posible acceder a su codigo fuente mostrado sin todos los comentarios pulsando en "Go to source code".
--! \section files Archivos documentados
--! - top.vhd
--! - display.vhd
--! - CD4RE.vhd
--! \section source Codigo fuente
--! - <A HREF=_t_o_p_8vhd_source.html><B> TOP.vhd Annotated source </B></A>
--! - <A HREF=_d_i_s_p_l_a_y_8vhd_source.html><B> DISPLAY.vhd Annotated source </B></A>
--! - <A HREF=_c_d4_r_e_8vhd_source.html><B> CD4RE.vhd Annotated source </B></A>
--! \section constraints Constraints
--! El archivo de constraints se puede encontrar en \ref Basys3_GPIO.xdc
--! \section reports Informes
--! Tal y como pide la guia, los informes de interes se pueden encontrar en \ref Informe_E/S  y en \ref Informe_Utilizacion
--! \section author Author
--! Carlos Manuel Gomez Jimenez, DNI: 76037985P

--! \page Informe_E/S 
--! \include io_report.txt
--! \page Informe_Utilizacion
--! \include synthesis_utilization.txt

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

--! Entidad de que contiene las entradas y salidas
entity TOP is
    Generic (
        --! \brief Tamano del vector contador calculado como se muestra en \ref CalculoN. 
        --! Parametro que se define en la entidad de un modulo y permite personalizar ciertos aspectos del diseno sin cambiar el codigo interno. Es como una "variable de configuracion" para el modulo.
        N: NATURAL := 17 
        );
          --! Clock Input
    Port (CLK: in STD_LOGIC;
          --! Entrada de los 16 interruptores de tipo std_logic_vector, ordenado siendo el 15 el MSB.
          SW: in STD_LOGIC_VECTOR (15 downto 0);
          --! \brief Entrada de los 5 botones de tipo std_logic_vector, ordenado siendo el 4 el MSB.
          --! \warning En la guia indica para el xdc: BTN[0]=BTNC; BTN[1]=BTNU; BTN[2]=BTNR; BTN[3]=BTND; BTN[4]=BTNL; No estan en orden.
          BTN: in STD_LOGIC_VECTOR (4 downto 0);
          --! Salida de los 16 LEDs de tipo std_logic_vector, ordenado siendo el 15 el MSB.
          LED: out STD_LOGIC_VECTOR (15 downto 0);
          --! Salida de los 8 catodos de los displays de tipo std_logic_vector, ordenado siendo el 7 el MSB.
          CAT: out STD_LOGIC_VECTOR (7 downto 0);
          --! Salida de los 4 anodos de los displays de tipo std_logic_vector, ordenado siendo el 3 el MSB.
          AN: out STD_LOGIC_VECTOR (3 downto 0));
end TOP;


--! Arquitectura de TOP.
architecture Behavioral of TOP is
    --------------------------  ALIAS
    --! Alias de reset interna
    alias reset_in: std_logic is BTN(0);
    --------------------------  SENALES
    --! Senal de reloj generada por el MMCM
    signal MCLK: std_logic;
    --! Senal que indica la estabilidad del MMCM
    signal locked: std_logic;
    --! Senal de reset interna dependiente de MMCM
    signal grst: std_logic;
    --! Senal para habilitar el contador de decisegundos.
    signal tick_freerun: std_logic;
    --! Senal de contador, usigned para que haga overflow de forma natural
    signal counter: unsigned(N-1 downto 0) := (others => '0');
    --! Senal con datos de entrada
    signal DDi: std_logic_vector(15 downto 0);

begin
    -----------------------------------------------------------------
    --  MMCM
    -----------------------------------------------------------------
    miMMCM: entity WORK.clk_wiz_0
    port map(
        clk_in1 => CLK, 
        reset => reset_in,
        clk_out1 => MCLK, 
        locked => locked
    );

    grst <= not locked; --! El reset global se activa mientras el MMCM no esta bloqueado, es decir, mientras no se ha estabilizado la senal de reloj generada.  
    
    
    -----------------------------------------------------------------
    -- CONTADOR FREERUNNING
    -----------------------------------------------------------------
    
    process(MCLK)
    begin
        if rising_edge(MCLK) then
            counter <= counter + 1;
        end if;
    end process;
    tick_freerun <= '1' when counter = N-1  else '0'; -- dura 1 system clock


    LED <= SW; --! Se asigna el valor de los interruptores SW a los LEDs, de modo que cada LED se enciende cuando su correspondiente interruptor está en alto.
    

end Behavioral;


 
