--! \file CD4RE.vhd
--! MODULO CD4RE encargado de implementar un contador BCD de 4 bits con enable y reset. El contador cuenta de 0 a 9 y luego vuelve a 0.
--! El contador tiene una salida de terminal count (TC) que se activa cuando el contador llega a 9, y una salida de carry out (CEO) que se activa cuando el contador incrementa de 9 a 0.
--!
--! \section plantilla Plantilla de instanciacion:
--!
--!     U0: entity WORK.CD4RE
--!     port map (
--!         C => MCLK, -- Señal de reloj a la que se serve el contador
--!         R => GRST, -- Señal de reset global, activa a 1. Pone el contador a 0.
--!         CE => TICK_FREERUN, -- Señal de enable del contador, activa a 1. El contador solo incrementa cuando esta señal esta activa.
--!         Q => Q0, -- Salida de 4 bits del contador, que representa el valor actual del contador en formato BCD.
--!         TC => open, -- Salida de terminal count, activa a 1 cuando el contador llega a 9.
--!         CEO => TICK_SECOND -- Salida de carry out, activa a 1 cuando el contador incrementa de 9 a 0.
--!     );
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

entity CD4RE is
    Port ( C : in STD_LOGIC;
           R : in STD_LOGIC;
           CE : in STD_LOGIC;
           Q : out STD_LOGIC_VECTOR (3 downto 0);
           TC : out STD_LOGIC;
           CEO : out STD_LOGIC);
end CD4RE;

architecture Behavioral of CD4RE is
    --! Senal registrada de salida de contador. Necesitamos leerla asi que no podemos leer directamente de la salida, y tampoco podemos hacer operaciones aritmeticas con un STD_LOGIC_VECTOR
    signal Qr: UNSIGNED(3 downto 0);
    --! Senal "futura" de la salida del contador, es +1 si el contador es <9 y CE esta activado. Cuando llegue a 9 su siguiente valor debe ser 0
    signal Qn: UNSIGNED(3 downto 0);
    --! Senal interna para poder leer de la salida TC
    --! Senal interna para poder leer de la salida TC
    signal TCr: STD_LOGIC;

begin
    
    process(C)
    begin
        if rising_edge(C) then
            if R = '1' then
            Qr <= (others => '0');
            elsif CE = '1' then
            Qr <= Qn;
            end if;
        end if;
    end process;
    
    -- LOGICA COMBINACIONAL FUERA DEL PROCESS
    -----------------------------------------
    
    -- LOGICA DE ESTADO SIGUIENTE
    Qn <= (others=>'0') when (R = '1') else 
          (Qr + 1) when (CE = '1' and Qr < 9) else 
          (others=>'0') when (CE = '1' and Qr = 9) else
          -- El contador no debe cambiar si no ocurre nada de lo anterior. La senal futura sera la actual.
          Qr;
    -- LOGICA DE LA SENAL INTERNA TC
    TCr <= '1' when Qr = 9 else '0';
    
    -- LOGICA DE LAS SALIDAS
    CEO <= '1' when (CE = '1' and TCr = '1') else '0';
    TC<= TCr;
    Q<=STD_LOGIC_VECTOR(Qr);
    
end Behavioral;
