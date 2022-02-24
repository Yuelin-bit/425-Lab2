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


type state_type is (start, r, w, r_memory, r_memwrite, r_memUpdate, w_memory);
signal state : state_type;
signal next_state : state_type;
-- 25 tag + 5 index + 2 offset.
-- Note: 2 offset is for words location, we need 4 times to r/w bytes.
-- After ignorance, 16 bit = 9 tag + 5 index + 2 offset.



-- cacheArray[32]
-- 128 data + 9 tag + 1 dirty + 1 valid = 139 bits
type cache_type is array (0 to 31) of std_logic_vector (138 downto 0);
signal cacheArray : cache_type;



begin
process (clock, reset)
begin

	if reset = '1' then
		state <= start;
	elsif (clock'event and clock = '1') then --rising edge
		state <= next_state;
	end if;
	
end process;	

process (s_read, s_write, m_waitrequest, state)

	variable index : INTEGER;	
	variable Offset : INTEGER := 0;
	variable counter : INTEGER := 0; -- 1 word = 4 bytes, counter <= 4
	variable temp : std_logic_vector (14 downto 0);
begin
	index := to_integer(unsigned(s_addr(6 downto 2)));
	Offset := to_integer(unsigned(s_addr(1 downto 0))) +1; -- 1,2,3,4


	case state is
	
		when start =>
            m_read <= '0';
            m_write <= '0';
        
			s_waitrequest <= '1';
			if s_read = '1' then --READ
				next_state <= r;
			elsif s_write = '1' then --WRITE
				next_state <= w;
			else
				next_state <= start;
			end if;
			
			
		--write data in cache
		when w => 
			if cacheArray(index)(137) = '1' and (cacheArray(index)(138) /= '1' or cacheArray(index)(136 downto 128) /= s_addr (31 downto 7)) and next_state /= start  then --If it the dirty and miss we have to write the previous date in memory.
				next_state <= w_memory;
			else
				cacheArray(index)(137) <= '1'; --mark dirty
				cacheArray(index)(138) <= '1';
				
				cacheArray(index)(127 downto 0)((Offset * 32) -1 downto 32 * (Offset - 1)) <= s_writedata;  --write data to cache
				cacheArray(index)(136 downto 128) <= s_addr (15 downto 7); 
				s_waitrequest <= '0';
				next_state <= start;
					
			end if;
			
			
		
		--write data in memory
		when w_memory => 	
			if counter <= 3 and m_waitrequest = '1' then --run 4 times
				temp := cacheArray(index)(135 downto 128) & s_addr (6 downto 0); -- We have  8 tag 5 index and 2 offset
				m_addr <= to_integer(unsigned (temp)) + counter ;
				m_write <= '1';
				m_read <= '0';
				m_writedata <= cacheArray(index)(127 downto 0) ((counter * 8) + 32 * (Offset - 1) + 7 downto  (counter * 8) + 32 * (Offset - 1)); -- locate the byte address
				counter := counter + 1;
				next_state <= w_memory; -- continue the loop
				
			elsif counter = 4 then --reach the 4
				cacheArray(index)(137) <= '1'; --mark dirty
				cacheArray(index)(138) <= '1';
				
				cacheArray(index)(127 downto 0)((Offset * 32) - 1 downto 32 * (Offset - 1)) <= s_writedata (31 downto 0); --write data to cache
				cacheArray(index)(136 downto 128) <= s_addr (15 downto 7); 

				counter := 0; --reset counter
				s_waitrequest <= '0';
				m_write <= '0';
				next_state <=start;
			else --m_waitrequest = '0'
				m_write <= '0';
				next_state <= w_memory;
			end if;
			
			
		--read data in cache
		when r =>
			if cacheArray(index)(138) = '1' and cacheArray(index)(136 downto 128) = s_addr (15 downto 7) then -- If hit, just raed data
			
				s_readdata <= cacheArray(index)(127 downto 0) ((Offset * 32) -1 downto 32 * (Offset - 1));
				s_waitrequest <= '0';
				next_state <= start;
			elsif cacheArray(index)(137) = '1' then --If it is a dirty miss, we write the data and read the data from memory.
				next_state <= r_memwrite;
			elsif cacheArray(index)(137) = '0' or  cacheArray(index)(137) = 'U' then ---If it is a clean miss, just read the data from memory.
				next_state <= r_memory;
			else
				next_state <= r;
			end if;
			
			
			
			
		when r_memwrite =>
			if counter < 4 and m_waitrequest = '1' and next_state /= r_memory then 
				temp := cacheArray(index)(135 downto 128) & s_addr (6 downto 0);
				m_addr <= to_integer(unsigned (temp)) + counter ;
				m_write <= '1';
				m_read <= '0';
                
				-- m_writedata <= cacheArray(index)(127 downto 0) ((counter * 8) + 7 + 32 * (Offset - 1) downto  (counter * 8) + 32 * (Offset - 1));
                -- need to unroll possible values of counter variable
                case counter is
                when 0 => m_writedata <= cacheArray(index)(127 downto 0) ((0 * 8) + 7 + 32 * (Offset - 1) downto  (0 * 8) + 32 * (Offset - 1));
                when 1 => m_writedata <= cacheArray(index)(127 downto 0) ((1 * 8) + 7 + 32 * (Offset - 1) downto  (1 * 8) + 32 * (Offset - 1));
                when 2 => m_writedata <= cacheArray(index)(127 downto 0) ((2 * 8) + 7 + 32 * (Offset - 1) downto  (2 * 8) + 32 * (Offset - 1));
                when 3 => m_writedata <= cacheArray(index)(127 downto 0) ((3 * 8) + 7 + 32 * (Offset - 1) downto  (3 * 8) + 32 * (Offset - 1));
                when others => report "Illegal value for counter" severity FAILURE;
                end case;
                
				counter := counter + 1;
				next_state <= r_memwrite;
			elsif counter = 4 then --read the data from memory.
				counter := 0;
				next_state <=r_memory;
			else
				m_write <= '0';
				next_state <= r_memwrite;
			end if;
			
			
			
		when r_memory =>
			if m_waitrequest = '1' then 
				m_addr <= to_integer(unsigned(s_addr (14 downto 0))) + counter;
				m_read <= '1';
				m_write <= '0';
				next_state <= r_memUpdate;
			else -- wait
				next_state <= r_memory;
			end if;
			
			
			
		when r_memUpdate =>
			if counter < 3 and m_waitrequest = '0' then 
            
				-- cacheArray(index)(127 downto 0)((counter * 8) + 7 + 32 * (Offset - 1) downto  (counter * 8) + 32 * (Offset - 1)) <= m_readdata;
                -- same as above, need to unroll possible values of variable counter
                case counter is
                when 0 => cacheArray(index)(127 downto 0)((0 * 8) + 7 + 32 * (Offset - 1) downto  (0 * 8) + 32 * (Offset - 1)) <= m_readdata;
                when 1 => cacheArray(index)(127 downto 0)((1 * 8) + 7 + 32 * (Offset - 1) downto  (1 * 8) + 32 * (Offset - 1)) <= m_readdata;
                when 2 => cacheArray(index)(127 downto 0)((2 * 8) + 7 + 32 * (Offset - 1) downto  (2 * 8) + 32 * (Offset - 1)) <= m_readdata;
                when others => report "Illegal value for counter" severity FAILURE;
                end case;
            
                counter := counter + 1;
				m_read <= '0';
				next_state <= r_memory; -- Go back to counter++
                
			elsif counter = 3 and m_waitrequest = '0' then 
                -- since counter is always 3 in this branch, use constant value instead of variable (counter = 3 in this branch)
				cacheArray(index)(127 downto 0)((3 * 8) + 7 + 32 * (Offset - 1) downto  (3 * 8) + 32 * (Offset - 1)) <= m_readdata;
				counter := counter + 1;
				m_read <= '0';
				next_state <= r_memUpdate;
			elsif counter = 4 then -- for the tag 
				s_readdata <= cacheArray(index)(127 downto 0) ((Offset * 32) -1 downto 32 * (Offset - 1));
				cacheArray(index)(136 downto 128) <= s_addr (15 downto 7); 
				cacheArray(index)(138) <= '1'; 
				cacheArray(index)(137) <= '0'; --Mark it clean
				m_read <= '0';
				m_write <= '0';
				s_waitrequest <= '0';
				counter := 0;
				next_state <= start;
			else
				next_state <= r_memUpdate;
			end if;

	end case;
end process;


end arch;