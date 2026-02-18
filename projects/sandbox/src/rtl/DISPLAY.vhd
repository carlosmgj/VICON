--! \file TOP.vhd
--! Archivo fuente VHDL.
--! \mainpage Prueba de evaluacion Final 21
--! -  Desarrollo de un pequeño core.
--! -  Uso de lógica combinacional y secuencial dentro del mismo core.
--! -  Documentar el modelo mediante breves comentarios.
--! -  La documentación debe facilitar la fácil reutilización del core.
--! -  Hacer uso del core creado en una sencilla prueba.
--! -  Analizar informes para extraer información
--! -  Hacer pruebas de verificación sobre placa para extraer información
--! -  Mejorar la destreza en el uso de las distintas herramientas que hemos utilizado hasta ahora
--! -  Revisar aquellos aspectos que en las pruebas de evaluación continua no quedaron bien terminados.
--!
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
          AN: out STD_LOGIC_VECTOR (3 downto 0));
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


 
