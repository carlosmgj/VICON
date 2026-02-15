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
--! El codigo fuente se encuentra en <A HREF=_t_o_p_8vhd_source.html><B> TOP.vhd Annotated source </B></A>.
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
    --signal namesignal: type (max downto min);
    --! Tipo enumerado que representa los distintos estados de la FSM
    type STATES is (s0,s1,s2);
    --! Registro para almacenar el estado actual de la FSM
    signal state_reg, state_next: STATES;
    --! La señal de reset (RST) la controlamos con BTN(0)
    alias RST: STD_LOGIC is SW(0);
    --! La señal de entrada A la controlamos con BTN(4)
    alias A: STD_LOGIC is BTN(4);
    --! La señal de entrada B la controlamos con BTN(2)
    alias B: STD_LOGIC is BTN(2);
    --! La señal de salida Y0 la conectaremos a LED(0)
    alias Y0: STD_LOGIC is LED(0);
    --! La señal de salida Y1 la conectaremos a LED(1)
    alias Y1: STD_LOGIC is LED(1);
    
    
    
    
begin
-- LED(5) se encenderá cuando estamos en el estado S0.
LED(5) <= '1' when state_reg = s0 else '0';
-- LED(6) se encenderá cuando estamos en el estado S1.
LED(6) <= '1' when state_reg = s1 else '0';
-- LED(7) se encenderá cuando estamos en el estado S2.
LED(7) <= '1' when state_reg = s2 else '0';
-- El resto de LED no los utilizaremos (los mantendremos apagados)
-- Los dígitos del display deben permanecer TODOS apagados
AN<= (others => '1');
------------ LOGICA SECUENCIAL

-- state register

process(CLK,RST)
begin
    --RESET ASINCRONO
    if RST ='1' then state_reg <= s0;
    --ESTADO ACTUAL REGISTRADO
    elsif rising_edge(CLK) then
        state_reg <= state_next;
    end if;                
end process;

-- next state logic

process (state_reg, A, B)
begin
    -- IMPORTANTE: ESTADO POR DEFECTO EN EL MISMO SITIO SI NO SE CUMPLEN LAS CONDICIONES
    state_next <= state_reg;
    case state_reg is
    when s0 =>
        if (A='1' AND B='1') then
            state_next <= s2;
        elsif (A='1' AND B = '0') then
            state_next <= s1;
        end if;
    when s1 =>
        if (A='1') then
            state_next <= s0;
        end if;
    when s2 => state_next <= s0;     
    end case;
end process;


-- Moore output logic
Y1 <= '1' when (state_reg = s0 or state_reg = s1) else '0';
-- Mealy output logic
Y0 <= '1' when a='1' and b='1' and state_reg = s0 else '0';

end Behavioral;
