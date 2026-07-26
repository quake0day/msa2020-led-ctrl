package require qsys
create_system {xcvr_sys}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}

# 主 PHY: 4 通道 duplex (QSFP), 正确三联组划分
add_instance phy altera_xcvr_native_s10_htile
set_instance_parameter_value phy channel_type GXT
set_instance_parameter_value phy anlg_voltage 1_1V
set_instance_parameter_value phy protocol_mode basic_enh
set_instance_parameter_value phy pma_mode basic
set_instance_parameter_value phy channels 4
set_instance_parameter_value phy set_data_rate 25781.25
set_instance_parameter_value phy set_cdr_refclk_freq 644.53125
set_instance_parameter_value phy enh_pcs_pma_width 64
set_instance_parameter_value phy enh_pld_pcs_width 64
set_instance_parameter_value phy duplex_mode duplex
set_instance_parameter_value phy tx_fifo_pfull 10
set_instance_parameter_value phy rx_fifo_pfull 10
set_instance_parameter_value phy enable_port_rx_seriallpbken 1

# 填充 PHY: 2 通道 TX-only (填满 6pack 的 2 个未用槽, GXT HIGH_PERF, 无 CDR PLL)
add_instance phyf altera_xcvr_native_s10_htile
set_instance_parameter_value phyf channel_type GXT
set_instance_parameter_value phyf anlg_voltage 1_1V
set_instance_parameter_value phyf protocol_mode basic_enh
set_instance_parameter_value phyf pma_mode basic
set_instance_parameter_value phyf channels 2
set_instance_parameter_value phyf set_data_rate 25781.25
set_instance_parameter_value phyf set_cdr_refclk_freq 644.53125
set_instance_parameter_value phyf enh_pcs_pma_width 64
set_instance_parameter_value phyf enh_pld_pcs_width 64
set_instance_parameter_value phyf duplex_mode tx
set_instance_parameter_value phyf tx_fifo_pfull 10

# 双 ATX PLL: 每三联组一个
foreach a {0 1} {
    add_instance atx$a altera_xcvr_atx_pll_s10_htile
    set_instance_parameter_value atx$a set_auto_reference_clock_frequency 644.53125
    set_instance_parameter_value atx$a primary_pll_buffer {GXT clock output buffer}
    set_instance_parameter_value atx$a enable_28G_local_atx_path 1
    set_instance_parameter_value atx$a set_output_clock_frequency 12890.625
}
# 主 PHY: 逻辑 ch0/ch3 在下三联组(atx0), ch1/ch2 在上三联组(atx1)
add_connection atx0.tx_serial_clk_gxt phy.tx_serial_clk0_ch0
add_connection atx0.tx_serial_clk_gxt phy.tx_serial_clk0_ch3
add_connection atx1.tx_serial_clk_gxt phy.tx_serial_clk0_ch1
add_connection atx1.tx_serial_clk_gxt phy.tx_serial_clk0_ch2
# 填充 PHY: ch0 在下三联组(atx0), ch1 在上三联组(atx1)
add_connection atx0.tx_serial_clk_gxt phyf.tx_serial_clk0_ch0
add_connection atx1.tx_serial_clk_gxt phyf.tx_serial_clk0_ch1

add_interface refclk clock sink
set_interface_property refclk EXPORT_OF atx0.pll_refclk0
add_interface refclk1 clock sink
set_interface_property refclk1 EXPORT_OF atx1.pll_refclk0
add_interface pll_locked conduit end
set_interface_property pll_locked EXPORT_OF atx0.pll_locked
add_interface pll_locked1 conduit end
set_interface_property pll_locked1 EXPORT_OF atx1.pll_locked

# 导出主 PHY 接口
foreach if [get_instance_interfaces phy] {
    if {[regexp {tx_serial_clk0} $if]} { continue }
    if {[catch {
        add_interface x_$if conduit end
        set_interface_property x_$if EXPORT_OF phy.$if
    } e]} {}
}
# 导出填充 PHY 接口 (前缀 f_)
foreach if [get_instance_interfaces phyf] {
    if {[regexp {tx_serial_clk0} $if]} { continue }
    if {[catch {
        add_interface f_$if conduit end
        set_interface_property f_$if EXPORT_OF phyf.$if
    } e]} {}
}
save_system xcvr_sys.qsys
puts "SAVED_OK"
