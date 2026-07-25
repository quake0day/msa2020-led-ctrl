# 实验3: QSFP0 收发器 PRBS 环回 -- IP 生成脚本
# 用法: qsys-script --script=make_ips.tcl --quartus-project=qsfp_prbs
# 生成: ip/xcvr0.ip (4ch 25.78G PHY), ip/atxpll0.ip, ip/rstctrl0.ip,
#       ip/issp_xcvr.ip (上位机控制/状态通道)
package require qsys

# ---- Native PHY: QSFP0 4 通道, 25.78125 Gbps, 增强 PCS basic 80bit ----
create_system {xcvr0}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance phy altera_xcvr_native_s10_htile
set_instance_property phy AUTO_EXPORT true
set_instance_parameter_value phy design_environment NATIVE
set_instance_parameter_value phy channel_type GXT
set_instance_parameter_value phy anlg_voltage 1_1V
set_instance_parameter_value phy set_cdr_refclk_freq 644.53125
set_instance_parameter_value phy protocol_mode basic_enh
set_instance_parameter_value phy pma_mode basic
set_instance_parameter_value phy duplex_mode duplex
set_instance_parameter_value phy channels 4
set_instance_parameter_value phy set_data_rate 25781.25
set_instance_parameter_value phy enable_simple_interface 1
set_instance_parameter_value phy enh_pcs_pma_width 64
set_instance_parameter_value phy enh_pld_pcs_width 64
set_instance_parameter_value phy tx_fifo_pfull 10
set_instance_parameter_value phy rx_fifo_pfull 10
set_instance_parameter_value phy bonded_mode pma_only
set_instance_parameter_value phy enable_port_rx_seriallpbken 1
save_system ip/xcvr0.ip

# ---- ATX PLL: 644.53125 MHz ref -> 12890.625 MHz (25.78125G 半率时钟) ----
create_system {atxpll0}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance pll altera_xcvr_atx_pll_s10_htile
set_instance_property pll AUTO_EXPORT true
set_instance_parameter_value pll set_auto_reference_clock_frequency 644.53125
set_instance_parameter_value pll set_output_clock_frequency 12890.625
set_instance_parameter_value pll primary_pll_buffer {GXT clock output buffer}
set_instance_parameter_value pll enable_28G_local_atx_path 1
set_instance_parameter_value pll enable_28G_output_frm_abv_atx 1
set_instance_parameter_value pll enable_28G_output_frm_blw_atx 1
set_instance_parameter_value pll enable_GXT_clock_source atx_lcl
save_system ip/atxpll0.ip

# ---- 收发器复位控制器: 4ch + 1 PLL, 100MHz 系统时钟, L-Tile ----
create_system {rstctrl0}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance rc altera_xcvr_reset_control_s10
set_instance_property rc AUTO_EXPORT true
set_instance_parameter_value rc CHANNELS 4
set_instance_parameter_value rc PLLS 1
set_instance_parameter_value rc SYS_CLK_IN_MHZ 100
set_instance_parameter_value rc TX_PLL_ENABLE 1
set_instance_parameter_value rc EN_PLL_CAL_BUSY 1
save_system ip/rstctrl0.ip

# ---- ISSP: 上位机控制/状态 (instance_id=XCV) ----
create_system {issp_xcvr}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance issp altera_in_system_sources_probes
set_instance_property issp AUTO_EXPORT true
set_instance_parameter_value issp source_width {16}
set_instance_parameter_value issp probe_width {96}
set_instance_parameter_value issp instance_id {XCV}
save_system ip/issp_xcvr.ip
