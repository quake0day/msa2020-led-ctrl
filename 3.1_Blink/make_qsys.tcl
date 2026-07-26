# 用 qsys-script 生成 jtag_sys.qsys:
#   jtag_master -- JTAG-Avalon 桥, Avalon 主接口导出给 led_ctrl_core
#   jtag2 + ram -- 对照实验: 第二个 JTAG 桥直连片内 RAM (纯官方通路,
#                  用于判断挂死问题是否与自写 RTL 有关)
#   issp        -- In-System Sources & Probes 备用控制通道 (单次移位,
#                  不依赖流式传输)
#   rst_release -- S10 配置完成信号 ninit_done (Critical Warning 20615)
package require qsys

create_system {jtag_sys}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
set_project_property HIDE_FROM_IP_CATALOG {true}

# ---- 时钟/复位桥: 多实例共享导出的 clk 与复位 ----
add_instance clk_br altera_clock_bridge
set_instance_parameter_value clk_br EXPLICIT_CLOCK_RATE {100000000.0}
add_instance rst_br altera_reset_bridge
set_instance_parameter_value rst_br SYNCHRONOUS_EDGES {deassert}

# ---- 主通路: JTAG-Avalon 桥 (导出) ----
add_instance jtag_master altera_jtag_avalon_master

# ---- 对照通路: 第二个 JTAG 桥 -> 片内 RAM ----
add_instance jtag2 altera_jtag_avalon_master
add_instance ram altera_avalon_onchip_memory2
set_instance_parameter_value ram memorySize {1024.0}
set_instance_parameter_value ram dataWidth {32}

# ---- ISSP 备用通道 ----
add_instance issp altera_in_system_sources_probes
set_instance_parameter_value issp source_width {16}
set_instance_parameter_value issp probe_width {32}
set_instance_parameter_value issp instance_id {LED}

# ---- Reset Release ----
add_instance rst_release altera_s10_user_rst_clkgate

# ---- 时钟连接 ----
add_connection clk_br.out_clk jtag_master.clk
add_connection clk_br.out_clk jtag2.clk
add_connection clk_br.out_clk ram.clk1
add_connection clk_br.out_clk rst_br.clk

# ---- 复位连接 ----
add_connection rst_br.out_reset jtag_master.clk_reset
add_connection rst_br.out_reset jtag2.clk_reset
add_connection rst_br.out_reset ram.reset1

# ---- 对照通路总线连接 ----
add_connection jtag2.master ram.s1
set_connection_parameter_value jtag2.master/ram.s1 baseAddress {0x0}

# ---- 导出 ----
add_interface clk clock sink
set_interface_property clk EXPORT_OF clk_br.in_clk

add_interface reset reset sink
set_interface_property reset EXPORT_OF rst_br.in_reset

add_interface master avalon master
set_interface_property master EXPORT_OF jtag_master.master

add_interface master_reset reset source
set_interface_property master_reset EXPORT_OF jtag_master.master_reset

add_interface ninit_done conduit end
set_interface_property ninit_done EXPORT_OF rst_release.ninit_done

add_interface issp_sources conduit end
set_interface_property issp_sources EXPORT_OF issp.sources

add_interface issp_probes conduit end
set_interface_property issp_probes EXPORT_OF issp.probes

save_system {jtag_sys.qsys}
