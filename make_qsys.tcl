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
set_instance_parameter_value issp2 probe_width {96}
set_instance_parameter_value issp2 instance_id {MEM}

# ---- Avalon 桥 (33bit 地址覆盖 8GB DDR4; FSM 实际可达前 4GB) ----
add_instance mm_bridge altera_avalon_mm_bridge
set_instance_parameter_value mm_bridge DATA_WIDTH {32}
set_instance_parameter_value mm_bridge ADDRESS_WIDTH {33}
set_instance_parameter_value mm_bridge USE_AUTO_ADDRESS_WIDTH {0}

# ---- Reset Release ----
add_instance rst_release altera_s10_user_rst_clkgate

# ---- EMIF DDR4 x4 (侦察版: 4 个物理槽全部例化, 定位哪个通道有内存)
# 内存条: HMA81GR7CJR8N-XN (8GB 1Rx8 ECC RDIMM, 3200 降跑 2400)
foreach i {0 1 2 3} {
    add_instance emif$i altera_emif_s10
    foreach {p v} {
        PROTOCOL_ENUM                   PROTOCOL_DDR4
        PHY_DDR4_MEM_CLK_FREQ_MHZ       1200.0
        PHY_DDR4_DEFAULT_REF_CLK_FREQ   false
        PHY_DDR4_USER_REF_CLK_FREQ_MHZ  150.0
        MEM_DDR4_SPEEDBIN_ENUM          DDR4_SPEEDBIN_2400
        MEM_DDR4_FORMAT_ENUM            MEM_FORMAT_RDIMM
        MEM_DDR4_NUM_OF_DIMMS           1
        MEM_DDR4_RANKS_PER_DIMM         1
        MEM_DDR4_CK_WIDTH               1
        MEM_DDR4_DQ_WIDTH               72
        MEM_DDR4_DQ_PER_DQS             8
        MEM_DDR4_ROW_ADDR_WIDTH         16
        MEM_DDR4_COL_ADDR_WIDTH         10
        MEM_DDR4_BANK_ADDR_WIDTH        2
        MEM_DDR4_BANK_GROUP_WIDTH       2
        MEM_DDR4_TCL                    17
        MEM_DDR4_WTCL                   16
        MEM_DDR4_DM_EN                  false
        MEM_DDR4_ALERT_PAR_EN           false
        MEM_DDR4_READ_DBI               false
        MEM_DDR4_WRITE_DBI              false
        CTRL_DDR4_ECC_EN                true
        CTRL_DDR4_ECC_AUTO_CORRECTION_EN true
    } {
        set_instance_parameter_value emif$i $p $v
    }
}

# ---- 时钟连接 ----
add_connection clk_br.out_clk jtag_master.clk
add_connection clk_br.out_clk mm_bridge.clk
add_connection clk_br.out_clk rst_br.clk

# ---- 复位连接 ----
add_connection rst_br.out_reset jtag_master.clk_reset
add_connection rst_br.out_reset mm_bridge.reset

# ---- 总线连接: 桥 -> EMIF2 (丝印 DIMM2 槽, 已确认插条) ----
add_connection mm_bridge.m0 emif2.ctrl_amm_0
set_connection_parameter_value mm_bridge.m0/emif2.ctrl_amm_0 baseAddress {0x0}

# ---- EMIF 复位 ----
foreach i {0 1 2 3} {
    add_connection rst_br.out_reset emif$i.global_reset_n
}

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

# ---- EMIF 导出: 每通道的 参考时钟 / RZQ / DDR4 引脚 / 校准状态 ----
foreach i {0 1 2 3} {
    add_interface ddr${i}_ref_clk clock sink
    set_interface_property ddr${i}_ref_clk EXPORT_OF emif$i.pll_ref_clk
    add_interface ddr${i}_oct conduit end
    set_interface_property ddr${i}_oct EXPORT_OF emif$i.oct
    add_interface ddr$i conduit end
    set_interface_property ddr$i EXPORT_OF emif$i.mem
    add_interface ddr${i}_status conduit end
    set_interface_property ddr${i}_status EXPORT_OF emif$i.status
}
# 未接数据通路的通道: ctrl_amm 导出到顶层挂空 (仅看校准)
foreach i {0 1 3} {
    add_interface ddr${i}_ctrl avalon slave
    set_interface_property ddr${i}_ctrl EXPORT_OF emif$i.ctrl_amm_0
}

# 诊断: 导出 4 通道的 emif_usr_clk (PLL 从 150MHz ref 生成的用户时钟),
# 顶层用频率计检测其是否翻转 -> 判断 ref clock 存在与 PLL 锁定
foreach i {0 1 2 3} {
    add_interface ddr${i}_usrclk clock source
    set_interface_property ddr${i}_usrclk EXPORT_OF emif$i.emif_usr_clk
}

save_system {jtag_sys.qsys}
