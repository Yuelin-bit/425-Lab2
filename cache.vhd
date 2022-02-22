library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768
);
port(
	clock : in std_logic;
	reset : in std_logic;
	
	-- Avalon interface --
	s_addr : in std_logic_vector (31 downto 0);
	s_read : in std_logic;
	s_readdata : out std_logic_vector (31 downto 0);
	s_write : in std_logic;
	s_writedata : in std_logic_vector (31 downto 0);
	s_waitrequest : out std_logic; 
    
	m_addr : out integer range 0 to ram_size-1;
	m_read : out std_logic;
	m_readdata : in std_logic_vector (7 downto 0);
	m_write : out std_logic;
	m_writedata : out std_logic_vector (7 downto 0);
	m_waitrequest : in std_logic
);
end cache;

architecture arch of cache is

type state_type is (start, r, w, r_memory, r_memwrite, r_memwait, w_memory);
signal state : state_type;
signal next_state : state_type;


-- 25 tag + 5 index + 2 offset.
-- Note: 2 offset is for words location, we need 4 times to r/w bytes.


-- Cache struct [32]
-- 128 data + 25 tag + 1 dirty + 1 valid
type cache_def is array (0 to 31) of std_logic_vector (154 downto 0);
signal cache2 : cache_def;



begin
process (clock, reset)
begin

	if reset = '1' then
		state <= start;
	elsif (clock'event and clock = '1') then
		state <= next_state;
	end if;
	
end process;	

process (s_read, s_write, m_waitrequest, state)

	variable index : INTEGER;	
	variable Offset : INTEGER := 0;
	variable off : INTEGER := Offset - 1;
	variable counter : INTEGER := 0;
	variable addr : std_logic_vector (14 downto 0);
begin
	index := to_integer(unsigned(s_addr(6 downto 2)));
	Offset := to_integer(unsigned(s_addr(1 downto 0))) + 1;
	off :=  Offset - 1;

	case state is
	
		when start =>
			s_waitrequest <= '1';
			if s_read = '1' then --READ
				next_state <= r;
			elsif s_write = '1' then --WRITE
				next_state <= w;
			else
				next_state <= start;
			end if;
			
		when r =>
			-- if valid and tags match
			if cache2(index)(154) = '1' and cache2(index)(152 downto 128) = s_addr (31 downto 7) then --HIT
				s_readdata <= cache2(index)(127 downto 0) ((Offset * 32) -1 downto 32 * (Offset - 1));
				s_waitrequest <= '0';
				next_state <= start;
			elsif cache2(index)(153) = '1' then --MISS DIRTY
				next_state <= r_memwrite;
			elsif cache2(index)(153) = '0' or  cache2(index)(153) = 'U' then --MISS CLEAN
				next_state <= r_memory;
			else
				next_state <= r;
			end if;
			
		when r_memwrite =>
			if counter < 4 and m_waitrequest = '1' and next_state /= r_memory then -- EVICT
				addr := cache2(index)(135 downto 128) & s_addr (6 downto 0);
				m_addr <= to_integer(unsigned (addr)) + counter ;
				m_write <= '1';
				m_read <= '0';
				m_writedata <= cache2(index)(127 downto 0) ((counter * 8) + 7 + 32 * (Offset - 1) downto  (counter * 8) + 32 * (Offset - 1));
				counter := counter + 1;
				next_state <= r_memwrite;
			elsif counter = 4 then -- NOW READ FROM MEM
				counter := 0;
				next_state <=r_memory;
			else
				m_write <= '0';
				next_state <= r_memwrite;
			end if;
			
		when r_memory =>
			if m_waitrequest = '1' then -- READ FROM MEM FIRST PART
				m_addr <= to_integer(unsigned(s_addr (14 downto 0))) + counter;
				m_read <= '1';
				m_write <= '0';
				next_state <= r_memwait;
			else
				next_state <= r_memory;
			end if;
			
		when r_memwait =>
			if counter < 3 and m_waitrequest = '0' then -- READ FROM MEM SECOND PART
				cache2(index)(127 downto 0)((counter * 8) + 7 + 32 * (Offset - 1) downto  (counter * 8) + 32 * (Offset - 1)) <= m_readdata;
				counter := counter + 1;
				m_read <= '0';
				next_state <= r_memory;
			elsif counter = 3 and m_waitrequest = '0' then -- EXTRA CYCLE TO ENSURE CACHE IS READ FIRST
				cache2(index)(127 downto 0)((counter * 8) + 7 + 32 * (Offset - 1) downto  (counter * 8) + 32 * (Offset - 1)) <= m_readdata;
				counter := counter + 1;
				m_read <= '0';
				next_state <= r_memwait;
			elsif counter = 4 then -- PLACE DATA READ FROM MEM ONTO OUTPUT
				s_readdata <= cache2(index)(127 downto 0) ((Offset * 32) -1 downto 32 * (Offset - 1));
				cache2(index)(152 downto 128) <= s_addr (31 downto 7); --Tag
				cache2(index)(154) <= '1'; --Valid
				cache2(index)(153) <= '0'; --Clean
				m_read <= '0';
				m_write <= '0';
				s_waitrequest <= '0';
				counter := 0;
				next_state <= start;
			else
				next_state <= r_memwait;
			end if;
		
		when w =>
			if cache2(index)(153) = '1' and next_state /= start and ( cache2(index)(154) /= '1' or cache2(index)(152 downto 128) /= s_addr (31 downto 7)) then --If it the dirty and miss we have to write the previous date in memory.
				next_state <= w_memory;
			else
				cache2(index)(153) <= '1'; -- DIRTY	
				cache2(index)(154) <= '1'; --Valid
				cache2(index)(127 downto 0)((Offset * 32) -1 downto 32 * (Offset - 1)) <= s_writedata; --DATA
				cache2(index)(152 downto 128) <= s_addr (31 downto 7); --TAG
				s_waitrequest <= '0';
				next_state <= start;
					
				end if;
		
		--write data in memory
		when w_memory => 	
			if counter <= 3 and m_waitrequest = '1' then --run 4 times
				addr := cache2(index)(135 downto 128) & s_addr (6 downto 0); -- We have  8 tag 5 index and 2 offset
				m_addr <= to_integer(unsigned (addr)) + counter ;
				m_write <= '1';
				m_read <= '0';
				m_writedata <= cache2(index)(127 downto 0) ((counter * 8) + 32 * (Offset - 1) + 7 downto  (counter * 8) + 32 * (Offset - 1)); -- locate the byte address
				counter := counter + 1;
				next_state <= w_memory; -- continue the loop
				
			elsif counter = 4 then --reach the 4
				cache2(index)(153) <= '1'; --mark dirty
				cache2(index)(154) <= '1';
				
				cache2(index)(127 downto 0)((Offset * 32) - 1 downto 32 * (Offset - 1)) <= s_writedata (31 downto 0); --write data to cache
				cache2(index)(152 downto 128) <= s_addr (31 downto 7); 

				counter := 0; --reset counter
				s_waitrequest <= '0';
				m_write <= '0';
				next_state <=start;
			else --m_waitrequest = '0'
				m_write <= '0';
				next_state <= w_memory;
			end if;
	end case;
end process;


end arch;