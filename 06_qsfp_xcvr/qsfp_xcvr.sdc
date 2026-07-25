# ============================================================================
# qsfp_xcvr.sdc  --  实验6 阶段1 收发器时序约束
# 收发器恢复时钟互相异步 + 复位同步器打断 (照搬 Corundum 520N_MX 约束)
# ============================================================================
set_time_format -unit ns -decimal_places 3

create_clock -name {clock_100}    -period 10.000 [get_ports {clock_100}]
create_clock -name {qsfp0_refclk} -period  1.551 [get_ports {qsfp0_refclk}]
create_clock -name {altera_reserved_tck} -period 62.500 {altera_reserved_tck}

derive_clock_uncertainty

set_clock_groups -asynchronous -group [get_clocks {clock_100}]
set_clock_groups -asynchronous -group [get_clocks {qsfp0_refclk}]
set_clock_groups -asynchronous -group {altera_reserved_tck}

# 复位同步器约束 proc
source sync_reset.sdc

# IO 打断
set_false_path -to [get_ports {led[*]}]

# 监视累加器 CDC (rx_clkout -> clock_100), 非数据路径
set_false_path -to [get_registers {*errsum*}]

# ---- 每个 PHY 的收发恢复时钟互相异步 + 复位同步器 ----
proc constrain_phy { inst } {
    set_clock_groups -asynchronous -group [get_clocks "${inst}|eth_xcvr_inst|tx_clkout|ch0"]
    set_clock_groups -asynchronous -group [get_clocks "${inst}|eth_xcvr_inst|rx_clkout|ch0"]
    set_clock_groups -asynchronous -group [get_clocks "${inst}|eth_xcvr_inst|profile0|tx_clkout|ch0"]
    set_clock_groups -asynchronous -group [get_clocks "${inst}|eth_xcvr_inst|profile0|rx_clkout|ch0"]
    set_clock_groups -asynchronous -group [get_clocks "${inst}|eth_xcvr_inst|profile1|tx_clkout|ch0"]
    set_clock_groups -asynchronous -group [get_clocks "${inst}|eth_xcvr_inst|profile1|rx_clkout|ch0"]
    constrain_sync_reset_inst "$inst|phy_tx_rst_reset_sync_inst"
    constrain_sync_reset_inst "$inst|phy_rx_rst_reset_sync_inst"
    constrain_sync_reset_inst "$inst|phy_tx_rst_req_reset_sync_inst"
    constrain_sync_reset_inst "$inst|phy_rx_rst_req_reset_sync_inst"
}

proc constrain_phy_quad { inst } {
    constrain_phy "${inst}|eth_xcvr_phy_1"
    constrain_phy "${inst}|eth_xcvr_phy_2"
    constrain_phy "${inst}|eth_xcvr_phy_3"
    constrain_phy "${inst}|eth_xcvr_phy_4"
}

constrain_phy_quad "u_qsfp0"
# PLL 状态异步输入的同步器首级打断
set_false_path -to [get_registers {*pll_lk_s[0]*}]
set_false_path -to [get_registers {*pll_cb_s[0]*}]
