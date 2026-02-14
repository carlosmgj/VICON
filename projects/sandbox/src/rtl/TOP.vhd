--! \file TOP.vhd
--! Archivo fuente VHDL.
--! \mainpage Proyecto SECUENCIAL
--! \section title1 Descripcion
--! \image html diagram.svg "Diagrama lógico"
--! Pasos a realizar:
--! Primer diseno secuencial con:
--! - Parametrizacion del diseno
--! - Conexion con MUX del EC21
--! - Diseno Jerarquico
--! \note El formato de comentario incluye ! para poder realizar documentacion dinamica con Doxygen. 
--! \section Uso
--! Acceder a la documentacion abriendo el archivo <b>index.html</b> dentro de la carpeta ./docs/html. <br>
--! En cada archivo (File), es posible acceder a su codigo fuente mostrado sin todos los comentarios pulsando en "Go to source code".
--! \section source Codigo fuente
--! La documentacion del codigo fuente se encuentra en \ref TOP.vhd
--! El codigo fuente se encuentra en <A HREF=_t_o_p_8vhd_source.html><B> TOP.vhd Annotated source </B></A> y en <A HREF=_c_d4_r_e_8vhd_source.html><B> CD4RE.vhd Annotated source </B></A>
--! \section constraints Constraints
--! El archivo de constraints se puede encontrar en \ref Basys3_GPIO.xdc
--! \section reports Informes
--! Tal y como pide la guia, los informes de interes se pueden encontrar en \ref Informe_E/S  y en \ref Informe_Utilizacion
--! \section author Author
--! Carlos Manuel Gomez Jimenez, DNI: 76037985P

--! \page CalculoN Calculo del Generico N
--!
--! \section Objetivo
--! Determinar el valor del generico \f$N\f$ para que el bit de mayor peso
--! del contador free-running conmute con un periodo aproximado de
--! \f$1\,\text{s}\f$, minimizando el error.
--!
--! \section Desarrollo
--! El bit mas significativo (MSB) de un contador binario divide la frecuencia
--! del reloj de entrada segun:
--!
--! \f[
--! F_{MSB} = \frac{F_{clk}}{2^N}
--! \f]
--!
--! Por tanto, el periodo asociado al MSB es:
--!
--! \f[
--! T_{MSB} = \frac{1}{F_{MSB}} = \frac{2^N}{F_{clk}}
--! \f]
--!
--! Si se desea un periodo aproximado de \f$T_{MSB} \approx 1\,\text{s}\f$,
--! debe cumplirse:
--!
--! \f[
--! 2^N \approx F_{clk}
--! \f]
--!
--! Finalmente, el valor optimo de \f$N\f$ se obtiene como:
--!
--! \f[
--! N \approx \log_2(F_{clk})
--! \f]
--! Para un reloj de \f$F_{clk} = 100\,\text{MHz}\f$:
--!
--! \f[
--! N \approx \log_2(100 \times 10^6) \approx 26.58
--! \f]
--!
--! Por tanto, el valor entero mas cercano es \f$N = 26\f$ o \f$N = 27\f$,
--! siendo estos los que proporcionan el menor error usando divisiones
--! por potencias de dos.
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
        N: NATURAL := 26 
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
    --! Vector declaration for counter
    signal COUNTER: STD_LOGIC_VECTOR (N-1 downto 0);
    --! primer grupo mas significativo de 4 bits del free-running que que definen el numero del TERCER digito (AN(1)) de izda a dcha.
    alias SW_DIGIT_3: STD_LOGIC_VECTOR (3 downto 0) is COUNTER(N-1 downto N-4);
    --! segundo grupo mas significativo de 4 bits del free-running que definen el numero del CUARTO digito (AN(0)) de izda a dcha.
    alias SW_DIGIT_4: STD_LOGIC_VECTOR (3 downto 0) is COUNTER(N-5 downto N-8);
    --! Cuatro interruptores (del SW8 al SW11) que definen el numero del SEGUNDO digito (AN(2)) de izda a dcha.
    signal SW_DIGIT_2: STD_LOGIC_VECTOR (3 downto 0);
    --! Cuatro interruptores (del SW12 al SW15) que definen el numero del PRIMER digito (AN(3)) de izda a dcha.
    alias SW_DIGIT_1: STD_LOGIC_VECTOR (3 downto 0) is SW(15 downto 12);
    --! Siete catodos (de A a G) que representan los siete segmentos de los displays
    signal CAT_NO_DP: STD_LOGIC_VECTOR (6 downto 0);
    --! Senal usada para conectar entre si dos modulos combinacionales internos
    signal COMB_CONN: STD_LOGIC_VECTOR (3 downto 0);

    --! Senal de contador FREERUNING interna para hacer operaciones
    signal Creg: UNSIGNED(N-1 downto 0);
    
begin


------------------------------------------------------------------------------------------
-- Instanciacion del modulo CD4RE
-- Reloj heredado del MSB del contador free-running
-- Reset y EN conectados como indica la especificacion.
------------------------------------------------------------------------------------------
U0: entity WORK.CD4RE
port map (
    C => COUNTER(N-1), 
    R => SW(0),
    CE => SW(1), 
    Q => SW_DIGIT_2, 
    TC => open,
    CEO => open
);

--Contador Free running sin inicializacion

Creg <= Creg +1 when rising_edge(CLK);
COUNTER <= STD_LOGIC_VECTOR(Creg);

-- Conectamos los 16 bit de mayor peso del contador a los LED
LED<=COUNTER(N-1 downto N-16);

-- Asignamos cada boton (exceptuando el boton central) al anodo de cada digito. 
-- BTNL=DIGIT1, BTND=DIGIT2, BTNR=DIGIT3, BTNU=DIGIT4 (Digitos contados de izquierda a derecha)
AN<= not BTN(4 downto 1);

-- Multiplexor 4 a 1
-- En los requisitos no se contempla que se puedan pulsar m?s de un boton a la vez, la aproximacion asumida es la siguiente 
-- pone el digito 4 en todos los que se activen si hay mas de uno
with BTN(4 downto 1) select
COMB_CONN <= SW_DIGIT_1 when "1000",
             SW_DIGIT_2 when "0100",
             SW_DIGIT_3 when "0010",
             SW_DIGIT_4 when others;


-- Conversor de HEX a 7 segmentos utilizando la tabla de verdad.
-- El orden esta invertido ya que CAT(0) corresponde al a que es ahora el bit menos significativo.             
with COMB_CONN(3 downto 0) select
CAT_NO_DP <= "1000000" when "0000",
             "1111001" when "0001",
             "0100100" when "0010",
             "0110000" when "0011",
             -----
             "0011001" when "0100",
             "0010010" when "0101",
             "0000010" when "0110",
             "1111000" when "0111",
             -----
             "0000000" when "1000",
             "0010000" when "1001",
             "0001000" when "1010",
             "0000011" when "1011",
             ------
             "1000110" when "1100",
             "0100001" when "1101",
             "0000110" when "1110",
             "0001110" when others;

-- Asignamos a los catodos el valor de la senal. (Se podria asignar directamente en el with select)
CAT(6 downto 0)<= CAT_NO_DP;     
-- El punto apagado en todos.
CAT(7)<='1';
end Behavioral;
