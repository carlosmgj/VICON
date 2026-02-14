--! \file CD4RE.vhd
--! Archivo modulo CD4RE.

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
