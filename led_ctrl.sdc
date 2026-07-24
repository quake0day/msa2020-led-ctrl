# led_ctrl 时序约束: 板载 100 MHz 时钟 (U28 Out2 -> PIN_AD6)
# JTAG (altera_reserved_tck) 相关约束由 JTAG-Avalon 桥 IP 自带 SDC 处理
create_clock -name clk100M -period 10.000 [get_ports clk100M]

# LED 为人眼观察的慢速输出, 不做严格时序分析
set_false_path -to [get_ports LED[*]]

# 诊断用时钟活动计数器的跨时钟域同步器 (两级同步, 本质异步安全)
set_false_path -from [get_registers {utog}] -to [get_registers {usy[0]}]
set_false_path -from [get_registers {rtog}] -to [get_registers {rsy[0]}]
