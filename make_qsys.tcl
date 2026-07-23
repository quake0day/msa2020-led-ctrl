# 用 qsys-script 生成 jtag_sys.qsys:
#   jtag_master -- JTAG-Avalon 桥 (备用: 本板 Catapult 驱动不支持其流式传输,
#                  换标准 USB-Blaster II 电缆时可用)
#   issp        -- LED 控制通道 (instance_id=LED, source16/probe32)
#   issp2       -- 内存读写通道 (instance_id=MEM, source96/probe64)
#   mm_bridge   -- 32bit Avalon 桥, s0 导出给 issp_mem_bridge FSM 驱动;
#                  m0 现接片内 RAM (64KB), DDR4 到位后改接 EMIF ctrl_amm
#                  (位宽适配由 Platform Designer 互连自动完成)
#   rst_release -- S10 配置完成信号 ninit_done (Critical Warning 20615)
package require qsys

create_system {jtag_sys}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
set_project_property HIDE_FROM_IP_CATALOG {true}

# ---- 时钟/复位桥 ----
add_instance clk_br altera_clock_bridge
set_instance_parameter_value clk_br EXPLICIT_CLOCK_RATE {100000000.0}
add_instance rst_br altera_reset_bridge
set_instance_parameter_value rst_br SYNCHRONOUS_EDGES {deassert}

# ---- JTAG-Avalon 桥 (备用) ----
add_instance jtag_master altera_jtag_avalon_master

# ---- ISSP: LED 控制 ----
add_instance issp altera_in_system_sources_probes
set_instance_parameter_value issp source_width {16}
set_instance_parameter_value issp probe_width {32}
set_instance_parameter_value issp instance_id {LED}

# ---- ISSP: 内存命令通道 ----
add_instance issp2 altera_in_system_sources_probes
set_instance_parameter_value issp2 source_width {96}
set_instance_parameter_value issp2 probe_width {64}
set_instance_parameter_value issp2 instance_id {MEM}

# ---- Avalon 桥 + 片内 RAM (64KB 测试内存) ----
add_instance mm_bridge altera_avalon_mm_bridge
set_instance_parameter_value mm_bridge DATA_WIDTH {32}
set_instance_parameter_value mm_bridge ADDRESS_WIDTH {31}
set_instance_parameter_value mm_bridge USE_AUTO_ADDRESS_WIDTH {0}
add_instance ram altera_avalon_onchip_memory2
set_instance_parameter_value ram memorySize {65536.0}
set_instance_parameter_value ram dataWidth {32}

# ---- Reset Release ----
add_instance rst_release altera_s10_user_rst_clkgate

# ---- 时钟连接 ----
add_connection clk_br.out_clk jtag_master.clk
add_connection clk_br.out_clk mm_bridge.clk
add_connection clk_br.out_clk ram.clk1
add_connection clk_br.out_clk rst_br.clk

# ---- 复位连接 ----
add_connection rst_br.out_reset jtag_master.clk_reset
add_connection rst_br.out_reset mm_bridge.reset
add_connection rst_br.out_reset ram.reset1

# ---- 总线连接: 桥 -> RAM ----
add_connection mm_bridge.m0 ram.s1
set_connection_parameter_value mm_bridge.m0/ram.s1 baseAddress {0x0}

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

add_interface mem_sources conduit end
set_interface_property mem_sources EXPORT_OF issp2.sources
add_interface mem_probes conduit end
set_interface_property mem_probes EXPORT_OF issp2.probes

add_interface mem avalon slave
set_interface_property mem EXPORT_OF mm_bridge.s0

save_system {jtag_sys.qsys}
