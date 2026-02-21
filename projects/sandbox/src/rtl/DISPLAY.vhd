--! \file DISPLAY.vhd
--! MODULO DISPLAY encargado de mostrar los valores de 4 nibbles en los displays.
--!  Se muestra un nibble en cada display, y se selecciona el nibble a mostrar con los interruptores SW.
--! El modulo utiliza un contador Free-Running para multiplexar los displays y mostrar los valores de forma continua.
--!
--! \section plantilla Plantilla de instanciacion:
--!
--!     Instancia_display: entity work.DISPLAY
--!         Generic Map (N => N) --! Se asigna el valor del parametro
--!         Port Map (
--!             C => MCLK, --! Se conecta la entrada MCLK de TOP a la entrada C de DISPLAY.
--!             DD => SW, --! Se conecta la entrada SW de TOP a la entrada
--!             CAT => CAT, --! Se conecta la salida CAT de DISPLAY a la salida CAT de TOP.
--!             AN => AN --! Se conecta la salida AN de DISPLAY a la salida AN de TOP.
--!         );
--!
--! \author Carlos Manuel Gomez Jimenez; DNI: 76037985P
--! \date 2024-06



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
entity DISPLAY is
    Generic (
        N: NATURAL := 26 
       );
          --! Clock Input of 100MHz
    Port (C: in STD_LOGIC;
          --! Entrada de los 4 nibbles que definirán el número a mostrar en cada display.
          DD: in STD_LOGIC_VECTOR (15 downto 0);
          --! Salida de los 8 catodos de los displays de tipo std_logic_vector, ordenado siendo el 7 el MSB.
          CAT: out STD_LOGIC_VECTOR (7 downto 0);
          --! Salida de los 4 anodos de los displays de tipo std_logic_vector, ordenado siendo el 3 el MSB.
          AN: out STD_LOGIC_VECTOR (3 downto 0);
          --! Entrada para la iluminacion de los puntos
          DP: in STD_LOGIC_VECTOR (3 downto 0));
end DISPLAY;


--! Arquitectura de DISPLAY.
architecture Behavioral of DISPLAY is    
     --! Bits correspondientes a cada led del display.
    signal sseg: STD_LOGIC_VECTOR(6 downto 0);
    --! HEX correspondiente al nibble a mostrar.
    signal hex: STD_LOGIC_VECTOR(3 downto 0);
    --! Señal de salida del contador FREE RUN.
    signal q_reg:UNSIGNED(N-1 downto 0);
    --! Señal futura del contador FREE RUNNING.
    signal q_next:UNSIGNED(N-1 downto 0);
    --! Señal que indica si el punto del display debe estar encendido o apagado.
    signal dot: STD_LOGIC;
    --! Nibble correspondiente al número a mostrar en cada display.
    signal Hin0, Hin1, Hin2, Hin3: STD_LOGIC_VECTOR(3 downto 0);
    --! Señal que elije qué digito mostrar en cada momento.
    signal sel: STD_LOGIC_VECTOR(1 downto 0);


begin

----------------------------------------------------------------------------------------------------------
--            CONTADOR FREE RUNNING
-----------------------------------------------------------------------------------------------------------
--! Proceso que actualiza el contador FREE RUNNING en cada flanco de subida del reloj.
process(C)
begin
    if rising_edge(C) then
        q_reg <= q_next;
    end if;
end process;

-- Incremento del contador FREE RUNNING. Como ambos son UNSIGNED, el valor se reiniciará a 0 al llegar a su valor máximo (overflow).
q_next <= q_reg + 1;

----------------------------------------------------------------------------------------------------------
--            MULTIPLEXOR 4 a 1
-----------------------------------------------------------------------------------------------------------
sel <= std_logic_vector(q_reg(N-1 downto N-2));  -- Los 2 bits más significativos del contador controlan el multiplexor.

--! Proceso que controla el multiplexor, con una lista de sensibilidad que incluye todas las entradas.
process(sel,Hin0,Hin1,Hin2,Hin3)  -- Lista de sensibilidad con todas las entradas.
begin
    case sel is
        when "00" => 
            hex <= Hin0;  -- Si sel=00, se muestra el número correspondiente a Hin0.
            an <= "1110";  -- Se enciende el display 0 (AN(0)=0) y se apagan los demás (AN(1,2,3)=1).
        when "01" =>
            hex <= Hin1;  -- Si sel=01, se muestra el número correspondiente a Hin1.
            an <= "1101";  -- Se enciende el display 1 (AN(1)=0) y se apagan los demás (AN(0,2,3)=1).
        when "10" =>
            hex <= Hin2;  -- Si sel=10, se muestra el número correspondiente a Hin2.
            an <= "1011";  -- Se enciende el display 2 (AN(2)=0) y se apagan los demás (AN(0,1,3)=1).
        when others =>
            hex <= Hin3;  -- Si sel=11, se muestra el número correspondiente a Hin3.
            an <= "0111";  -- Se enciende el display 3 (AN(3)=0) y se apagan los demás (AN(0,1,2)=1).
    end case;
end process;         


----------------------------------------------------------------------------------------------------------
--            EXTRACCION DE LOS NIBBLES DE LA ENTRADA
-----------------------------------------------------------------------------------------------------------

Hin0 <= DD(3 downto 0);   -- Nibble 0 (menos significativo)
Hin1 <= DD(7 downto 4);   -- Nibble 1
Hin2 <= DD(11 downto 8);  -- Nibble 2
Hin3 <= DD(15 downto 12); -- Nibble 3 (más significativo)

----------------------------------------------------------------------------------------------------------
--            DECODIFICADOR HEX7SEG
-----------------------------------------------------------------------------------------------------------

--! Conversor de HEX a 7 segmentos utilizando la tabla de verdad.
--! El orden esta invertido ya que CAT(0) corresponde al a que es ahora el bit menos significativo.             
with hex(3 downto 0) select
    sseg <=  "1000000" when "0000",
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

dot<= '1';  -- Todos los puntos a OFF
cat <= dot & sseg;  -- Concatenacion punto(MSB)+ digitos(LSB)

    
end Behavioral;


 
