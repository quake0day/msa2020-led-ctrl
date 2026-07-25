create_clock -name clock_100 -period 10.000 [get_ports clock_100]
derive_clock_uncertainty
# I2C 100kHz 慢速, ISSP JTAG 异步: 打断路径
set_false_path -from [get_ports i2c_*] -to *
set_false_path -from * -to [get_ports {i2c_* led[*]}]
