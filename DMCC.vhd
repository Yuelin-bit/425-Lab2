library ieee;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

entity DMCC is
port (clk : in std_logic;
      reset : in std_logic;
      input : in std_logic_vector(7 downto 0);
      output : out std_logic
  );
end DMCC;

architecture behavioral of DMCC is
begin
end behavioral;