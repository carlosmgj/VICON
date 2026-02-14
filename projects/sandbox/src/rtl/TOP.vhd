--! \file TOP.vhd
--! Archivo fuente VHDL.
--! \mainpage Proyecto HEX7SEG
--! \section title1 Descripcion
--! Pasos a realizar:
--! Nueva version del primer diseno:
--! - El convertidor de HEXADECIMAL a 7 segmentos
--! - Sin usar operadores l?gicos
--! - Valores distintos en los distintos digitos.
--!
--! Internamente el modelo incluira dos (2) modulos combinacionales:
--! - Un multiplexor 4 a 1 que seleccionara uno de los 4 vectores creados con ayuda de los alias. 
--! La salida del multiplexor (un vector de 4 bit, que es la senal interna declarada en la l?nea 40) sera la entrada al convertidor Hexadecimal a 7 segmentos.
--! El convertidor Hexadecimal a 7 segmentos, PERO ahora modelado con alguna de las sentencias estudiadas en este modulo, ya sea secuencial o concurrente.
--! \note El formato de comentario incluye ! para poder realizar documentacion dinamica con Doxygen. 
--! \section Uso
--! Acceder a la documentacion abriendo el archivo <b>index.html</b> dentro de la carpeta ./docs/html. <br>
--! En cada archivo (File), es posible acceder a su codigo fuente mostrado sin todos los comentarios pulsando en "Go to source code".
--! \section source Codigo fuente
--! La documentacion del codigo fuente se encuentra en \ref TOP.vhd
--! El codigo fuente se encuentra en <A HREF=_t_o_p_8vhd_source.html><B> TOP.vhd Annotated source </B></A>
--! \section constraints Constraints
--! El archivo de constraints se puede encontrar en \ref Basys3_GPIO.xdc
--! \section author Author
--! Carlos Manuel Gomez Jimenez, DNI: 76037985P


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

--! Entidad de que contiene las entradas y salidas
entity TOP is
          --! Entrada de los 16 interruptores de tipo std_logic_vector, ordenado siendo el 15 el MSB.
    Port (SW: in STD_LOGIC_VECTOR (15 downto 0);
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
    --! Cuatro interruptores (del SW0 al SW3) que definen el numero del CUARTO digito
    alias SW_DIGIT_4: STD_LOGIC_VECTOR (3 downto 0) is SW(3 downto 0);
    --! Cuatro interruptores (del SW4 al SW7) que definen el numero del TERCER digito
    alias SW_DIGIT_3: STD_LOGIC_VECTOR (3 downto 0) is SW(7 downto 4);
    --! Cuatro interruptores (del SW8 al SW11) que definen el numero del SEGUNDO digito
    alias SW_DIGIT_2: STD_LOGIC_VECTOR (3 downto 0) is SW(11 downto 8);
    --! Cuatro interruptores (del SW12 al SW15) que definen el numero del PRIMER digito
    alias SW_DIGIT_1: STD_LOGIC_VECTOR (3 downto 0) is SW(15 downto 12);
    --! Siete catodos (de A a G) que representan los siete segmentos de los displays
    signal CAT_NO_DP: STD_LOGIC_VECTOR (6 downto 0);
    --! Senal usada para conectar entre si dos modulos combinacionales internos
    signal COMB_CONN: STD_LOGIC_VECTOR (3 downto 0);
    
    

begin
--! Asignamos cada LED a su interruptor correspondiente, indicando con la luz que el SW esta a 1.
LED<=SW;
--! Asignamos cada boton (exceptuando el boton central) al anodo de cada digito. 
--! BTNL=DIGIT1, BTND=DIGIT2, BTNR=DIGIT3, BTNU=DIGIT4 (Digitos contados de izquierda a derecha)
AN<= not BTN(4 downto 1);

--! Multiplexor 4 a 1
--! En los requisitos no se contempla que se puedan pulsar m?s de un boton a la vez, la aproximacion asumida es la siguiente 
--! pone el digito 4 en todos los que se activen si hay mas de uno
--! OPC1:
with BTN(4 downto 1) select
COMB_CONN <= SW_DIGIT_1 when "1000",
             SW_DIGIT_2 when "0100",
             SW_DIGIT_3 when "0010",
             SW_DIGIT_4 when others;
--! OPC2:
--! Realmente con los 4 botones que tenemos como "selector", podriamos hacer un mux de 16 a 1. 
--! Asumimos que es v?lido ?nicamente cuando se pulsa un boton al mismo tiempo.
--! Cuando no sea asi, se mostrar? una F en todos los displays que hablite cada boton.
-- with BTN(4 downto 1) select
-- COMB_CONN <= SW_DIGIT_1 when "1000",
--              SW_DIGIT_2 when "0100",
--              SW_DIGIT_3 when "0010",
--              SW_DIGIT_4 when "0001",
--              "1111" when others;

--! Conversor de HEX a 7 segmentos utilizando la tabla de verdad.
--! El orden esta invertido ya que CAT(0) corresponde al a que es ahora el bit menos significativo.             
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

--! Asignamos a los catodos el valor de la senal. (Se podria asignar directamente en el with select)
CAT(6 downto 0)<= CAT_NO_DP;     
--! El punto apagado en todos.
CAT(7)<='1';
end Behavioral;
