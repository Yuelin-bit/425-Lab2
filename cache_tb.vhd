library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache_tb is
end cache_tb;

architecture behavior of cache_tb is

component cache is
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
end component;

component memory is 
GENERIC(
    ram_size : INTEGER := 32768;
    mem_delay : time := 10 ns;
    clock_period : time := 1 ns
);
PORT (
    clock: IN STD_LOGIC;
    writedata: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
    address: IN INTEGER RANGE 0 TO ram_size-1;
    memwrite: IN STD_LOGIC;
    memread: IN STD_LOGIC;
    readdata: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
    waitrequest: OUT STD_LOGIC
);
end component;
	
-- test signals 
signal reset : std_logic := '0';
signal clk : std_logic := '0';
constant clk_period : time := 1 ns;

signal s_addr : std_logic_vector (31 downto 0);
signal s_read : std_logic;
signal s_readdata : std_logic_vector (31 downto 0);
signal s_write : std_logic;
signal s_writedata : std_logic_vector (31 downto 0);
signal s_waitrequest : std_logic;

signal m_addr : integer range 0 to 2147483647;
signal m_read : std_logic;
signal m_readdata : std_logic_vector (7 downto 0);
signal m_write : std_logic;
signal m_writedata : std_logic_vector (7 downto 0);
signal m_waitrequest : std_logic; 

begin

-- Connect the components which we instantiated above to their
-- respective signals.
dut: cache 
port map(
    clock => clk,
    reset => reset,

    s_addr => s_addr,
    s_read => s_read,
    s_readdata => s_readdata,
    s_write => s_write,
    s_writedata => s_writedata,
    s_waitrequest => s_waitrequest,

    m_addr => m_addr,
    m_read => m_read,
    m_readdata => m_readdata,
    m_write => m_write,
    m_writedata => m_writedata,
    m_waitrequest => m_waitrequest
);

MEM : memory
port map (
    clock => clk,
    writedata => m_writedata,
    address => m_addr,
    memwrite => m_write,
    memread => m_read,
    readdata => m_readdata,
    waitrequest => m_waitrequest
);
				

clk_process : process
begin
  clk <= '0';
  wait for clk_period/2;
  clk <= '1';
  wait for clk_period/2;
end process;

test_process : process
begin

-- put your tests here


	-- test case 0
	s_addr <= std_logic_vector(to_unsigned(10, s_addr'length));
	s_writedata <= X"12";
	s_write <= '1';
	wait until rising_edge(s_waitrequest);
	-- try to read what was just written
	s_write <= '0';
	s_read <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"12" report "write unsuccesful" severity error;
	
	
	-- test case 1: Read, valid block, tag equal, not dirty
	-- setup: read from address before test so that data is in cache
	-- setup: write to address, evict to write to main mem, read addr again to load into cache
	s_addr <= std_logic_vector(to_unsigned(11, s_addr'length));
	s_write <= '1';
	s_read <= '0';
	s_writedata <= X"21";
	wait until rising_edge(s_waitrequest);
	-- evict block by writing data to address in same block but with different tag
	s_addr <= std_logic_vector(to_unsigned(139, s_addr'length));
	s_write <= '1';
	s_read <= '0';
	s_writedata <= X"212";
	wait until rising_edge(s_waitrequest);
	-- finally read original addr (11) again so that it will already loaded into cache for test
	s_addr <= std_logic_vector(to_unsigned(11, s_addr'length));
	s_write <= '0';
	s_read <= '1';
	wait until rising_edge(s_waitrequest);
	-- Begin test
	s_addr <= std_logic_vector(to_unsigned(11, s_addr'length));
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"21" report "test 1 failed" severity error;
	
	
	-- test case 2 Read, valid, tag equal, dirty = DIRTY HIT
	-- setup: write something to cache so that it will be dirty
	s_addr <= std_logic_vector(to_unsigned(12, s_addr'length));
	s_read <= '0';
	s_write <= '1';
	s_writedata <= X"22";
	wait until rising_edge(s_waitrequest);
	-- begin test
	s_addr <= std_logic_vector(to_unsigned(12, s_addr'length));
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"22" report "test 2 failed" severity error;
	
	
	-- test case 3: Read, not valid block, tag equal, not dirty, = CLEAN MISS
	-- write some data to addr 29 in main memory
	m_addr <= 29; -- std_logic_vector(to_unsigned(29, m_addr'length));
	m_write <= '1';
	m_read <= '0';
	m_writedata <= X"33";
	wait until rising_edge(m_waitrequest);
	-- simply try to load from addr that is not in cache yet (diff block index than above addresses)
	s_addr <= std_logic_vector(to_unsigned(29, s_addr'length));
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"33" report "test 3 failed" severity error;
	
	
	-- test case 4: read, tag equal, not valid block, dirty bit  = DIRTY MISS , but doesn't exist
	-- redudant test case due to case 3, as dirty bit doesn't matter if block is not valid
	
	
	-- test case 5: read, tag not equal, valid block, not dirty = CLEAN MISS
	-- setup: write some data to main memory that we will try to retrieve in cache
	m_addr <= 404;--std_logic_vector(to_unsigned(404, m_addr'length)); -- tag = 3, index = 5, offset = 0
	m_read <= '0';
	m_write <= '1';
	m_writedata <= X"55";
	wait until rising_edge(m_waitrequest);
	-- setup: read from mem into cache block with index 5
	s_addr <= std_logic_vector(to_unsigned(148, s_addr'length)); -- tag = 1, index = 5, offset = 0
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	-- begin test: read from mem into same cache block (index 5), different tag
	s_addr <= std_logic_vector(to_unsigned(404, s_addr'length));
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"55" report "test 5 failed" severity error;
	
	
	-- test case 6: read, tag not eqaul, valid block, dirty bit = DIRTY MISS
	-- setup write some data to main memory to try and retrieve into cache
	m_addr <= 152;--std_logic_vector(to_unsigned(152, m_addr'length)); -- tag = 1, index = 6, offset = 0
	m_read <= '0';
	m_write <= '1';
	m_writedata <= X"66";
	wait until rising_edge(m_waitrequest);
	-- setup: write data to same block with diff tag to make block 6 dirty
	s_addr <= std_logic_vector(to_unsigned(408, s_addr'length)); -- tag = 3, index = 6, offset = 0
	s_read <= '0';
	s_write <= '1';
	s_writedata <= x"69";
	wait until rising_edge(s_waitrequest);
	-- begin test: read from mem into cache block 6
	s_addr <= std_logic_vector(to_unsigned(152, s_addr'length));
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"66" report "test 6 failed" severity error;
	
	
	-- test case 7: read, not matching tags, invalid block, not dirty block
	-- redudant test case, same as test case 3, because if block is invalid, then tags matching or not is irrelevant because
	-- nothing to match tags with.
	
	
	-- test case 8: read, not matching tags, invalid block, dirty block
	-- redudant same as about. Same as test case 3.
	-- If block is invalid, then tag matching and dirty bit don't make a difference.
	
	
	-- test case 9: write, matching tags, valid block, not dirty
	-- setup: write value to main mem
	m_addr <= 164; --std_logic_vector(to_unsigned(164, m_addr'length)); -- tag = 1, index = 9, offset = 0
	m_read <= '0';
	m_write <= '1';
	m_writedata <= X"99";
	wait until rising_edge(m_waitrequest);
	-- setup: read from an addr
	s_addr <= std_logic_vector(to_unsigned(164, s_addr'length)); -- tag = 1, index = 9, offset = 0
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	-- begin test: write to same address as above
	s_addr <= std_logic_vector(to_unsigned(164, s_addr'length));
	s_read <= '0';
	s_write <= '1';
	s_writedata <= X"9900";
	wait until rising_edge(s_waitrequest);
	-- check that data in cache is correct and data in memory is old
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"9900" report "test 9 failed - A" severity error;
	m_read <= '1';
	m_write <= '0';
	wait until rising_edge(m_waitrequest);
	assert m_readdata = x"99" report "test 9 failed - B" severity error;
	
	
	-- test case 10: write, matching tags, valid block, dirty bit
	-- setup: write data to main mem. Read data so it is loaded into cache block
	-- write to cache block to make it dirty. 
	-- then attempt to write to cache block again with same tags
	m_addr <= 168; --std_logic_vector(to_unsigned(168, m_addr'length)); -- tag = 1, index = 10; offset = 0
	m_read <= '0';
	m_write <= '1';
	m_writedata <= X"1010";
	wait until rising_edge(m_waitrequest);
	s_addr <= std_logic_vector(to_unsigned(168, s_addr'length));
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	s_read <= '0';
	s_write <= '1';
	s_writedata <= X"1015";
	wait until rising_edge(s_waitrequest);
	-- begin test: write to dirty block again
	s_writedata <= X"1017";
	wait until rising_edge(s_waitrequest);
	-- read from cache to ensure correct value was stored
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"1017" report "test 10 failed - A" severity error;
	-- main memory data should still be original value, never written to from cache in this test case
	m_read <= '1';
	m_write <= '0';
	wait until rising_edge(m_waitrequest);
	assert m_readdata = x"1010" report "test 10 failed - B" severity error;
	
	
	-- test case 11: write, matching tags, invalid block, not dirty
	-- setup: write to previously invalid (ie empty) block, ie: write to block without reading from it first
	-- first write some data to main memory
	m_addr <= 172; -- std_logic_vector(to_unsigned(172 , m_addr'length)); -- tag = 1, block = 11, offset = 0
	m_read <= '0';
	m_write <= '1';
	m_writedata <= X"1111";
	wait until rising_edge(m_waitrequest);
	-- being test:
	s_addr <= std_logic_vector(to_unsigned(172, s_addr'length)); -- tag = 1, block = 11, offset = 0
	s_read <= '0';
	s_write <= '1';
	s_writedata <= X"1115";
	wait until rising_edge(s_waitrequest);
	-- assert: cache has updated value, and main mem has old value
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"1115" report "test 11 failed - A" severity error;
	m_read <= '1';
	m_write <= '0';
	wait until rising_edge(m_waitrequest);
	assert m_readdata = x"1111" report "test 11 failed - B" severity error;
	
	
	-- test case 12: write, matching tags, invalid block, dirty bit
	-- redudant test case, same as test case 11, because if block is invalid, then dirty bit doesn't mean anything
	
	
	-- test case 13: write, not matching tags, valid block, not dirty bit
	-- setup: write data to main memory
	m_addr <= 180; -- std_logic_vector(to_unsigned(180, m_addr'length));
	m_read <= '0';
	m_write <= '1';
	m_writedata <= X"1313";
	wait until rising_edge(m_waitrequest);
	-- read data from main mem into cache
	s_addr <= std_logic_vector(to_unsigned(180, s_addr'length)); -- tag = 1, block = 13, offset = 0
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	-- begin test: attempt to write to same block as above, but different tag
	s_addr <= std_logic_vector(to_unsigned(436, s_addr'length)); -- tag = 3, block = 13, offset = 0
	s_read <= '0';
	s_write <= '1';
	s_writedata <= x"1315";
	wait until rising_edge(s_waitrequest);
	-- assert contents of cache block 13 is correct
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"1315" report "test 13 failed" severity error;
	
	
	-- test case 14: write, not matching tags, valid block, dirty bit
	-- setup: write to block, then try to write to same block diff tag
	m_addr <= 184; -- std_logic_vector(to_unsigned(184, m_addr'length)); -- tag = 1; block = 14; offset = 0
	m_read <= '0';
	m_write <= '1';
	m_writedata <= x"1414";
	wait until rising_edge(m_waitrequest);
	-- attempt to write to address 184 through cache. This will make block 14 dirty
	s_addr <= std_logic_vector(to_unsigned(184, s_addr'length));
	s_read <= '0';
	s_write <= '1';
	s_writedata <= x"1415";
	wait until rising_edge(s_waitrequest);
	-- being test: write to block 14 with different tags
	s_addr <= std_logic_vector(to_unsigned(440, s_addr'length)); -- tag = 3; block = 14; offset = 0
	s_read <= '0';
	s_write <= '1';
	s_writedata <= x"1499";
	wait until rising_edge(s_waitrequest);
	-- assert that value stored in cache block 14 is correct
	s_read <= '1';
	s_write <= '0';
	wait until rising_edge(s_waitrequest);
	assert s_readdata = x"1499" report "test 14 failed" severity error;
	
	
	-- test case 15: write, not matching tags, invalid block, not dirty
	-- redudant test case due to test 11
	-- if block is invalid, then tags matching and dirty bit are irrelevant, so this test case is same as 11
	
	
	-- test case 16: write, not matching tags, invalid block, dirty bit
	-- redudant test case due to test 11
	-- if block is invalid, then tags matching and dirty bit are irrelevant, so this test case is same as 11
	
	
end process;
	
end;