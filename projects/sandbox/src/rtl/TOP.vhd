--! \file TOP.vhd
--! Archivo fuente VHDL.
--! \mainpage Proyecto FSM
--! \section title1 Descripcion
--! \image html diagram.svg "Diagrama logico"
--! \note Duracion aproximada 90 minutos
--!
--! Pasos a realizar:
--! - Modelado de una FSM
--! - Introducción a la simulación de un modelo VHDL
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
    --signal namesignal: type (max downto min);
    
    
begin

end Behavioral;
