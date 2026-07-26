# 集成收发器子系统: PHY + ATX PLL 在同一 Platform Designer 系统内连接,
# 让 PD 用 GXT 专用时钟网络布局。
# 关键 (踩坑): 25.78G GXT 时钟连接必须是
#   ATX(enable_mcgb + enable_hfreq_clk).mcgb_serial_clk -> phy.tx_serial_clk0
#   且 phy 参数顺序敏感 (duplex/fifo/lpbk 须在 data_rate/pcs_width 之后设),
#   否则 add_connection 报 "Cannot connect"。
package require qsys

create_system {xcvr_sys}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
set_project_property HIDE_FROM_IP_CATALOG {true}

# ---- Native PHY: 4x25.78125 Gbps GXT, enhanced PCS basic 64bit ----
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

# ---- ATX PLL: MCGB high-freq path (GXT), 644.53125 -> 12890.625 MHz ----
add_instance atx altera_xcvr_atx_pll_s10_htile
set_instance_parameter_value atx set_auto_reference_clock_frequency 644.53125
set_instance_parameter_value atx enable_mcgb 1
set_instance_parameter_value atx enable_hfreq_clk 1
set_instance_parameter_value atx set_output_clock_frequency 12890.625

# ---- GXT high-freq clock connection (Intel native+pll rule) ----
add_connection atx.mcgb_serial_clk phy.tx_serial_clk0

# ---- Export: external 644.53125 refclk feeds ATX ----
add_interface refclk clock sink
set_interface_property refclk EXPORT_OF atx.pll_refclk0

# ---- Export PHY transceiver and user interfaces ----
foreach if {tx_serial_data rx_serial_data tx_parallel_data rx_parallel_data
            tx_analogreset tx_digitalreset rx_analogreset rx_digitalreset
            tx_analogreset_stat tx_digitalreset_stat
            rx_analogreset_stat rx_digitalreset_stat
            tx_cal_busy rx_cal_busy tx_clkout rx_clkout
            tx_coreclkin rx_coreclkin rx_cdr_refclk0
            rx_seriallpbken rx_is_lockedtoref rx_is_lockedtodata} {
    add_interface x_$if conduit end
    set_interface_property x_$if EXPORT_OF phy.$if
}

# ---- Export ATX status ----
add_interface x_pll_locked conduit end
set_interface_property x_pll_locked EXPORT_OF atx.pll_locked
add_interface x_pll_cal_busy conduit end
set_interface_property x_pll_cal_busy EXPORT_OF atx.pll_cal_busy

save_system xcvr_sys.qsys
