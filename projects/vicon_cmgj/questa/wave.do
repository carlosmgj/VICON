onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {TOP - Entradas/Salidas}
add wave -noupdate /testbench/u_dut/reset
add wave -noupdate /testbench/u_dut/sclk
add wave -noupdate /testbench/u_dut/sdata
add wave -noupdate -group WR_FIFO /testbench/u_dut/i2c_wr_push
add wave -noupdate -group WR_FIFO /testbench/u_dut/done
add wave -noupdate -group WR_FIFO /testbench/u_dut/i2c_wr_full
add wave -noupdate -group WR_FIFO /testbench/u_dut/i2c_wr_data
add wave -noupdate -group WR_FIFO /testbench/u_dut/i2c_wr_empty
add wave -noupdate -group RD_FIFO /testbench/u_dut/i2c_rd_full
add wave -noupdate -group RD_FIFO /testbench/u_dut/i2c_rd_pop
add wave -noupdate -group RD_FIFO /testbench/u_dut/i2c_rd_data
add wave -noupdate -group RD_FIFO /testbench/u_dut/i2c_rd_empty
add wave -noupdate -group FSM /testbench/u_dut/u_i2c/state
add wave -noupdate -group FSM /testbench/u_dut/i2c_start
add wave -noupdate -group FSM /testbench/u_dut/i2c_rw
add wave -noupdate -group FSM /testbench/u_dut/i2c_num_regs
add wave -noupdate -group FSM /testbench/u_dut/i2c_addr_reg
add wave -noupdate -group FSM /testbench/u_dut/i2c_busy
add wave -noupdate -group FSM /testbench/u_dut/i2c_done
add wave -noupdate -group FSM /testbench/u_dut/i2c_error
add wave -noupdate -divider OTHER
add wave -noupdate /testbench/u_dut/state
add wave -noupdate /testbench/u_dut/fill_cnt
add wave -noupdate /testbench/u_dut/locked
add wave -noupdate /testbench/u_dut/rst_final
add wave -noupdate /testbench/u_dut/rd_buf
add wave -noupdate /testbench/u_dut/rd_cnt
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {13087 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {124 ns} {22665 ns}
