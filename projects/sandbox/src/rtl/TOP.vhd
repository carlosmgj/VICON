--! \file TOP.vhd
--! Archivo fuente VHDL.
--! \mainpage Proyecto FIFO
--! \section title1 Descripcion
--! Modelado de una FIFO basada en memoria RAM
--! Primer diseno secuencial con:
--! Definicion del interfaz de E/S de la FIFO
--! - Modelado VHDL y sintesis de alguna de las alternativas de memoria interna de la FPGA.
--! - Modelado VHDL de la logica de control
--! - Modelado VHDL de la logica de estado
--! \warning ESTE ES UN BLOQUE BASICO DE LOS QUE SE UTILIZAN EN EL TFM VICON
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
--! \page lutram_vhdl 
--! \section desc_push Detalle de la implementación
--! - La única diferencia: NO existe la posibilidad de inicializar los registros
--! - Se genera un bloque de RAM de doble puerto
--! - No se genera lógica de decodificación y de multiplexación: Solo son necesarios 4 SLICE
--! @verbatim
--! process(CLK)
--! begin
--!     if rising_edge(CLK) then
--!         if wr_en = '1' then 
--!             array_reg(to_integer(unsigned(w_addr))) <= w_data;
--!         end if;
--!     end if;
--! end process;
--! r_data <= array_reg(to_integer(unsigned(r_addr)));
--! @endverbatim
--!
--! - SI QUEREMOS CREAR MEMORIA LUTRAM Y NO USAR FF, EL MODELO NO DEBE CONTEMPLAR FUNCION DE RESET 
--! - TAMPOCO SALDRÁ EN LA LISTA DE SENSIBILIDAD DEL PROCESO
--! - LA LECTURA SE MODELA FUERA DEL PROCESO REGISTRADO

    
    
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

--! \brief Entidad de que contiene las entradas y salidas
--! \details El interfaz del modulo FIFO debe incluir las E/S que se muestran en la figura adjunta
--! \image html FIFO_ES.png "Diagrama logico"
--! El interfaz del modulo FIFO debe incluir los genericos B y W que nos permiten
--! parametrizar el tamano de la memoria RAM interna, tal y como se presento en el
--! material didactico (modulo 32, pagina 5 de 8):
--! - B es la anchura de bus de direcciones de la RAM interna (valor por defecto 6)
--! - W es la anchura de los buses de datos (DIN y DOUT) (valor por defecto 8)

entity FIFO is
    Generic (
        --! Anchura de bus de direcciones de la RAM interna
        B: integer := 6;
        --! Anchura de los buses de datos (DIN y DOUT)
        W: integer := 8 
        );
          --! Entrada de reloj
    Port (CLK: in STD_LOGIC;
          --! Entrada de reset.
          RST: in STD_LOGIC;
          --! Entrada de DATOS
          DIN: in STD_LOGIC_VECTOR (W-1 downto 0);
          --! Senal para meter un dato en la FIFO (Presente en DIN)
          PUSH: in STD_LOGIC;
          --! Senal que indica que la FIFO esta llena (1)
          FULL: out STD_LOGIC;
          --! Salida de DATOS
          DOUT: out STD_LOGIC_VECTOR (W-1 downto 0);
          --! Senal para sacar un dato de la FIFO (Estará en DOUT);
          POP: in STD_LOGIC;
          --! Senal que indica que la FIFO esta vacia (1)
          EMPTY: out STD_LOGIC
          ); 
end FIFO;


--! Arquitectura de la FIFO.
architecture Behavioral of FIFO is
    --! ARRAY de VECTORES de LONGITUD 2^B
    type fifo_mem is array(0 to (2**B)-1) of STD_LOGIC_VECTOR(W-1 downto 0);
    --! Senal que modela la RAM (Lineas de teoria: \ref lutram_vhdl)
    signal mem: fifo_mem := (others=> (others=>'0'));
    --! Contador/puntero de lectura
    signal rd_ptr: INTEGER range 0 to (2**B)-1 := 0;
    --! Contador/puntero de escritura
    signal wr_ptr: INTEGER range 0 to (2**B)-1 := 0;
    --! Senal interna de full \ref FIFO::FULL
    signal fifo_full: STD_LOGIC := '0';
    --! Senal interna de empty \ref FIFO::EMPTY
    signal fifo_empty: STD_LOGIC := '0';
    --! Senal de habilitacion de escritura en la RAM
    signal wr_en: STD_LOGIC := '0';
    --! Senal de habilitacion de lectura en la RAM
    signal rd_en: STD_LOGIC := '0';
   
begin

    -- MODELADO DEL BLOQUE DE RAM INTERNO
    -- LUTRAM = Memoria Distribuida

    -- Proceso de escritura (PUSH)
    process(CLK, RST)
    begin
        if RST = '1' then
            wr_ptr <= 0;
            fifo_full <= '0';
        elsif rising_edge(CLK) then
            if (PUSH = '1' and  fifo_full='0') then
                mem(wr_ptr) <= DIN;
                wr_ptr <= (wr_ptr + 1) mod (2**B);  -- Incrementar y hacer el wrap-around
            end if;
        end if;
    end process;

    -- Proceso de lectura (POP)
    process(CLK, RST)
    begin
        if RST = '1' then
            rd_ptr <= 0;
            fifo_empty <= '1';
        elsif rising_edge(CLK) then
            if POP = '1' and fifo_empty='0' then
                DOUT <= mem(rd_ptr);
                rd_ptr <= (rd_ptr + 1) mod (2**B);  -- Incrementar y hacer el wrap-around
            end if;
        end if;
    end process;

    -- L?gica para los indicadores FULL y EMPTY
    process(wr_ptr, rd_ptr)
    begin
        if wr_ptr = rd_ptr then
            fifo_empty <= '1';  -- FIFO vac?a si los punteros son iguales
            fifo_full <= '0';
        elsif (wr_ptr + 1) mod (2**B) = rd_ptr then
            fifo_empty <= '0';
            fifo_full <= '1';  -- FIFO llena si el puntero de escritura ha alcanzado el puntero de lectura
        else
            fifo_empty <= '0';
            fifo_full <= '0';  -- FIFO no está llena ni vac?a
        end if;
    end process;

    -- Asignaci?n de se?ales de salida
    FULL <= fifo_full;
    EMPTY <= fifo_empty;
end Behavioral;


 
