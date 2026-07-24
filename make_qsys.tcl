# jtag_sys: 单通道 DDR4 诊断版 (丝印 DIMM0)
#   emif0     -- DDR4 RDIMM 1Rx8 64bit, PAR/ALERT 启用, 时序由 IP 自动推导,
#                cal_debug 导出 -> mm_bridge (经 ISSP 读校准报告)
#   i2c       -- Avalon I2C 主机 (板级 I2C AC28/AB28), 读内存条 SPD
#   issp/issp2-- LED 控制 + 内存/调试命令通道 (Catapult JTAG 不支持流式,
#                一切上位机通信走 ISSP)
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

# ---- ISSP: LED 控制 / 内存命令通道 ----
add_instance issp altera_in_system_sources_probes
set_instance_parameter_value issp source_width {16}
set_instance_parameter_value issp probe_width {32}
set_instance_parameter_value issp instance_id {LED}

add_instance issp2 altera_in_system_sources_probes
set_instance_parameter_value issp2 source_width {96}
set_instance_parameter_value issp2 probe_width {96}
set_instance_parameter_value issp2 instance_id {MEM}

# ---- Avalon 桥 (36bit: DDR4 8GB @0x0, I2C @0x2_0000_0000,
#      cal_debug 2GB @0x2_8000_0000) ----
add_instance mm_bridge altera_avalon_mm_bridge
set_instance_parameter_value mm_bridge DATA_WIDTH {32}
set_instance_parameter_value mm_bridge ADDRESS_WIDTH {36}
set_instance_parameter_value mm_bridge USE_AUTO_ADDRESS_WIDTH {0}

# ---- Reset Release ----
add_instance rst_release altera_s10_user_rst_clkgate

# ---- I2C 主机 (读 DIMM SPD; 板级总线 SCL=AC28 SDA=AB28) ----
add_instance i2c altera_avalon_i2c
set_instance_parameter_value i2c FIFO_DEPTH {8}

# ---- EMIF DDR4 单通道: HMA81GR7CJR8N-XN (8GB 1Rx8 PC4-3200AA RDIMM) ----
# 按建议: PAR/ALERT 启用(A/C lane 放置), TCL/WTCL 不手工锁定(IP 自动推导),
# DM on / DBI off / ECC off (对齐 Intel 官方 S10 四通道 RDIMM 参考设计)
add_instance emif0 altera_emif_s10
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
    MEM_DDR4_DQ_WIDTH               64
    MEM_DDR4_DQ_PER_DQS             8
    MEM_DDR4_ROW_ADDR_WIDTH         16
    MEM_DDR4_COL_ADDR_WIDTH         10
    MEM_DDR4_BANK_ADDR_WIDTH        2
    MEM_DDR4_BANK_GROUP_WIDTH       2
    MEM_DDR4_DM_EN                  true
    MEM_DDR4_READ_DBI               false
    MEM_DDR4_WRITE_DBI              false
    MEM_DDR4_ALERT_PAR_EN           true
    MEM_DDR4_ALERT_N_PLACEMENT_ENUM DDR4_ALERT_N_PLACEMENT_AC_LANES
    MEM_DDR4_ALERT_N_AC_LANE        0
    MEM_DDR4_ALERT_N_AC_PIN         10
    CTRL_DDR4_ECC_EN                false
    CTRL_DDR4_ECC_AUTO_CORRECTION_EN false
    DIAG_DDR4_EXPORT_SEQ_AVALON_SLAVE CAL_DEBUG_EXPORT_MODE_EXPORT
} {
    set_instance_parameter_value emif0 $p $v
}

# ---- 时钟/复位连接 ----
foreach inst {jtag_master mm_bridge rst_br} {
    add_connection clk_br.out_clk $inst.clk
}
add_connection clk_br.out_clk i2c.clock
add_connection rst_br.out_reset jtag_master.clk_reset
add_connection rst_br.out_reset mm_bridge.reset
add_connection rst_br.out_reset i2c.reset_sink
add_connection clk_br.out_clk emif0.cal_debug_clk
add_connection rst_br.out_reset emif0.cal_debug_reset_n

# ---- 总线: 桥 -> DDR4 数据口 / I2C / cal_debug ----
add_connection mm_bridge.m0 emif0.ctrl_amm_0
set_connection_parameter_value mm_bridge.m0/emif0.ctrl_amm_0 baseAddress {0x0}
add_connection mm_bridge.m0 i2c.csr
set_connection_parameter_value mm_bridge.m0/i2c.csr baseAddress {0x200000000}
add_connection mm_bridge.m0 emif0.cal_debug
set_connection_parameter_value mm_bridge.m0/emif0.cal_debug baseAddress {0x280000000}

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

add_interface i2c_serial conduit end
set_interface_property i2c_serial EXPORT_OF i2c.i2c_serial

# ---- EMIF 导出 ----
add_interface ddr0_ref_clk clock sink
set_interface_property ddr0_ref_clk EXPORT_OF emif0.pll_ref_clk
add_interface ddr0_oct conduit end
set_interface_property ddr0_oct EXPORT_OF emif0.oct
add_interface ddr0 conduit end
set_interface_property ddr0 EXPORT_OF emif0.mem
add_interface ddr0_status conduit end
set_interface_property ddr0_status EXPORT_OF emif0.status
add_interface ddr0_usrclk clock source
set_interface_property ddr0_usrclk EXPORT_OF emif0.emif_usr_clk

save_system {jtag_sys.qsys}
