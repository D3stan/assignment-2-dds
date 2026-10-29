onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_student_ss/dut/clk_in
add wave -noupdate /tb_student_ss/dut/rst
add wave -noupdate -divider APB
add wave -noupdate /tb_student_ss/dut/PADDR
add wave -noupdate /tb_student_ss/dut/PWRITE
add wave -noupdate /tb_student_ss/dut/PENABLE
add wave -noupdate /tb_student_ss/dut/PSEL
add wave -noupdate /tb_student_ss/dut/PWDATA
add wave -noupdate /tb_student_ss/dut/PRDATA
add wave -noupdate /tb_student_ss/dut/PREADY
add wave -noupdate /tb_student_ss/dut/PSLVERR
add wave -noupdate -divider {Student_area_0 CSR}
add wave -noupdate /tb_student_ss/dut/csr_data_ready
add wave -noupdate /tb_student_ss/dut/csr_done
add wave -noupdate /tb_student_ss/dut/csr_busy
add wave -noupdate /tb_student_ss/dut/acc_start
add wave -noupdate /tb_student_ss/dut/acc_finish
add wave -noupdate /tb_student_ss/dut/ibuf_waddr
add wave -noupdate /tb_student_ss/dut/obuf_raddr
add wave -noupdate -divider {IBUF BRAM ports}
add wave -noupdate /tb_student_ss/dut/ibuf_wr_en
add wave -noupdate /tb_student_ss/dut/ibuf_wr_addr
add wave -noupdate /tb_student_ss/dut/ibuf_wr_data
add wave -noupdate /tb_student_ss/dut/ibuf_rd_en
add wave -noupdate /tb_student_ss/dut/ibuf_rd_addr
add wave -noupdate /tb_student_ss/dut/ibuf_rd_data
add wave -noupdate -divider {OBUF BRAM ports}
add wave -noupdate /tb_student_ss/dut/obuf_wr_en
add wave -noupdate /tb_student_ss/dut/obuf_wr_addr
add wave -noupdate /tb_student_ss/dut/obuf_wr_data
add wave -noupdate /tb_student_ss/dut/obuf_rd_en
add wave -noupdate /tb_student_ss/dut/obuf_rd_addr
add wave -noupdate /tb_student_ss/dut/obuf_rd_data
add wave -noupdate -divider {pixel_acc}
add wave -noupdate /tb_student_ss/dut/i_acc/u_fsm/state
add wave -noupdate /tb_student_ss/dut/i_acc/start
add wave -noupdate /tb_student_ss/dut/i_acc/finish
add wave -noupdate /tb_student_ss/dut/i_acc/rd_en
add wave -noupdate -radix unsigned /tb_student_ss/dut/i_acc/ibuf_rd_addr
add wave -noupdate -radix hexadecimal /tb_student_ss/dut/i_acc/ibuf_rd_data
add wave -noupdate -radix unsigned /tb_student_ss/dut/i_acc/fetch_pos
add wave -noupdate /tb_student_ss/dut/i_acc/shift_en
add wave -noupdate /tb_student_ss/dut/i_acc/wr_en
add wave -noupdate -radix unsigned /tb_student_ss/dut/i_acc/obuf_wr_addr
add wave -noupdate -radix unsigned /tb_student_ss/dut/i_acc/wr_col
add wave -noupdate -radix unsigned /tb_student_ss/dut/i_acc/wr_row
add wave -noupdate -radix hexadecimal /tb_student_ss/dut/i_acc/obuf_wr_data
add wave -noupdate /tb_student_ss/dut/i_acc/rd_row_end
add wave -noupdate /tb_student_ss/dut/i_acc/wr_row_end
add wave -noupdate /tb_student_ss/dut/i_acc/wr_col_end
add wave -noupdate -divider {cache}
add wave -noupdate -radix hexadecimal /tb_student_ss/dut/i_acc/u_cache/fetch_pos_decoded
add wave -noupdate -radix hexadecimal /tb_student_ss/dut/i_acc/u_cache/u_bottom_line/out_words
TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 400
configure wave -valuecolwidth 150
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
configure wave -timelineunits ns
update
