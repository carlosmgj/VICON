onerror {resume}
radix define color_fsm {
    "0 ST_CAM_RESET_ASSERT -color Orange" "1 ST_CAM_RESET_WAIT -color Cyan",
    "2 ST_PAGE_SEL_FILL -color Yellow" "3 ST_PAGE_SEL_START -color White",
    "4 ST_PAGE_SEL_WAIT -color Blue" "5 ST_CHIPID_RD_START -color White",
    "6 ST_CHIPID_RD_WAIT -color Blue" "7 ST_CHIPID_RD_DRAIN -color Magenta",
    "8 ST_FINISH -color Green" "9 ST_ERROR -color Red",
    -default default
}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider FSM
add wave -noupdate -radix color_fsm -radixenum symbolic -radixshowbase 1 /testbench/u_dut/s_state
add wave -noupdate -radix unsigned /testbench/u_dut/s_init_cnt
add wave -noupdate -divider {Reloj y Reset}
add wave -noupdate /testbench/s_clk_base
add wave -noupdate /testbench/s_rst_raw
add wave -noupdate /testbench/u_dut/s_mclk
add wave -noupdate /testbench/u_dut/s_locked
add wave -noupdate -divider I2C
add wave -noupdate -height 30 /testbench/s_scl_bus
add wave -noupdate -radix unsigned /testbench/u_dut/s_i2c_busy
add wave -noupdate -height 30 /testbench/s_sda_bus
add wave -noupdate -radix unsigned /testbench/u_dut/s_i2c_done
add wave -noupdate -radix unsigned /testbench/u_dut/s_i2c_error
add wave -noupdate -divider <NULL>
add wave -noupdate -group i2c_agent /testbench/u_i2c_agent/scl_i
add wave -noupdate -group i2c_agent /testbench/u_i2c_agent/sda_io
add wave -noupdate -group i2c_agent /testbench/u_i2c_agent/s_regs_core
add wave -noupdate -group i2c_agent /testbench/u_i2c_agent/s_regs_ifp
add wave -noupdate -group i2c_agent /testbench/u_i2c_agent/s_reg_addr
add wave -noupdate -group i2c_agent /testbench/u_i2c_agent/s_debug_state
add wave -noupdate -divider -height 25 <NULL>
add wave -noupdate -group image_agent -divider -height 25 <NULL>
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/reset_i
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/fvalid_o
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/lvalid_o
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/data_o
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/s_state
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/s_col_cnt
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/s_row_cnt
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/s_blank_cnt
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/fvalid_r
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/lvalid_r
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/s_pix_num
add wave -noupdate -group image_agent /testbench/u_dut/g_cam_sim_on/u_cam_sim/clkin_i
add wave -noupdate -group image_agent /testbench/u_dut/s_mclk_div_cnt
add wave -noupdate -divider -height 25 <NULL>
add wave -noupdate -group {frame capture} -label PIXLCLK /testbench/u_dut/u_frame_capture/pixclk_i
add wave -noupdate -group {frame capture} -label RESET /testbench/u_dut/u_frame_capture/reset_i
add wave -noupdate -group {frame capture} -label {FRAME VALID} /testbench/u_dut/u_frame_capture/fvalid_i
add wave -noupdate -group {frame capture} -label {LINE VALID} /testbench/u_dut/u_frame_capture/lvalid_i
add wave -noupdate -group {frame capture} -label DATA /testbench/u_dut/u_frame_capture/data_i
add wave -noupdate -group {frame capture} -label {CAPTURE EN} /testbench/u_dut/u_frame_capture/capture_en_i
add wave -noupdate -group {frame capture} -label {FIFO DATA} /testbench/u_dut/u_frame_capture/fifo_data_o
add wave -noupdate -group {frame capture} -label {FIFO WR} /testbench/u_dut/u_frame_capture/fifo_wr_o
add wave -noupdate -group {frame capture} -label {FIFO FULL} /testbench/u_dut/u_frame_capture/fifo_full_i
add wave -noupdate -group {frame capture} -label {FRAME DONE} /testbench/u_dut/u_frame_capture/frame_done_o
add wave -noupdate -group {frame capture} -label OVERFLOW /testbench/u_dut/u_frame_capture/overflow_o
add wave -noupdate -group {frame capture} -label {FSM STATE} /testbench/u_dut/u_frame_capture/s_state
add wave -noupdate -group {frame capture} -label {BYTE CNT} /testbench/u_dut/u_frame_capture/s_byte_cnt
add wave -noupdate -group {frame capture} -label {COL CNT} /testbench/u_dut/u_frame_capture/s_col_cnt
add wave -noupdate -group {frame capture} -label {ROW CNT} /testbench/u_dut/u_frame_capture/s_row_cnt
add wave -noupdate -group {frame capture} -label OVERFLOW /testbench/u_dut/u_frame_capture/overflow_r
add wave -noupdate -divider -height 25 <NULL>
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/rst
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/wr_clk
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/rd_clk
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/din
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/wr_en
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/rd_en
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/dout
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/full
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/empty
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/wr_rst_busy
add wave -noupdate -group ASYNC_FIFO /testbench/u_dut/u_async_fifo/rd_rst_busy
add wave -noupdate -divider -height 25 <NULL>
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/clk_i
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/reset_i
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/fifo_data_i
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/fifo_empty_i
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/fifo_rd_en_o
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/txe_n_i
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/wr_n_o
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/adbus_o
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/tx_active_o
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/s_state
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/data_r
add wave -noupdate -group FTDI_CTRL /testbench/u_dut/u_ftdi_ctrl/fifo_rd_r
add wave -noupdate -divider -height 25 <NULL>
add wave -noupdate -group ftdi_agent -label PWRSAV /testbench/u_ftdi_agent/acbus_io(7)
add wave -noupdate -group ftdi_agent -label OE_N /testbench/u_ftdi_agent/acbus_io(6)
add wave -noupdate -group ftdi_agent -label CLKOUT /testbench/u_ftdi_agent/acbus_io(5)
add wave -noupdate -group ftdi_agent -label SIWU_N /testbench/u_ftdi_agent/acbus_io(4)
add wave -noupdate -group ftdi_agent -label WR_N /testbench/u_ftdi_agent/acbus_io(3)
add wave -noupdate -group ftdi_agent -label RD_N /testbench/u_ftdi_agent/acbus_io(2)
add wave -noupdate -group ftdi_agent -label TXE_N /testbench/u_ftdi_agent/acbus_io(1)
add wave -noupdate -group ftdi_agent -label RXF_N /testbench/u_ftdi_agent/acbus_io(0)
add wave -noupdate -group ftdi_agent -radix unsigned /testbench/u_ftdi_agent/adbus_i
add wave -noupdate -group ftdi_agent -divider -height 25 <NULL>
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {999590907 ps} 0} {{Cursor 2} {2342194721 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 553
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits us
update
WaveRestoreZoom {972465 ns} {1072465 ns}
