proc AddWaves {} {
	;#Add waves we're interested in to the Wave window
add wave sim:/cache_tb/clk
add wave sim:/cache_tb/clk_period
add wave sim:/cache_tb/reset
add wave sim:/cache_tb/s_addr
add wave sim:/cache_tb/s_read
add wave sim:/cache_tb/s_write
add wave sim:/cache_tb/s_readdata
add wave sim:/cache_tb/s_writedata
add wave sim:/cache_tb/s_waitrequest
add wave sim:/cache_tb/m_addr
add wave sim:/cache_tb/m_read
add wave sim:/cache_tb/m_write
add wave sim:/cache_tb/m_readdata
add wave sim:/cache_tb/m_writedata
}

vlib work

;# Compile components if any
vcom cache.vhd
vcom memory.vhd
vcom cache_tb.vhd
vcom memory_tb.vhd

;# Start simulation
vsim cache_tb

;# Generate a clock with 1ns period
force -deposit clk 0 0 ns, 1 0.5 ns -repeat 1 ns

;# Add the waves
AddWaves

;# Run for 20000 ns
run 20000ns
