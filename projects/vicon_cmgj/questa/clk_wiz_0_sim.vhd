library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity clk_wiz_0 is
    Port ( 
        clk_out1 : out STD_LOGIC;
        reset    : in  STD_LOGIC;
        locked   : out STD_LOGIC;
        clk_in1  : in  STD_LOGIC
    );
end clk_wiz_0;

architecture sim of clk_wiz_0 is
begin
    process(clk_in1, reset)
    begin
        if reset = '1' then
            clk_out1 <= '0';
            locked   <= '0';
        else
            clk_out1 <= clk_in1;
            locked   <= '1';
        end if;
    end process;
end sim;