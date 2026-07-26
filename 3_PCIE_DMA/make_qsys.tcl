# pcie_dma_sys: MSA-2020 独立 PCIe 最小实验 (Gen3x8 Avalon-MM)
#   主机把 FPGA 的 256KB 片内 RAM 映射进 BAR0, 经 PCIe 直接读写 ->
#   FPGA<->主机的 PCIe 数据搬运基座 (host-driven / PIO over PCIe)。
#
#   pcie       -- altera_pcie_s10_hip_avmm_bridge, Gen3x8, devkit=NONE,
#                 VID 0x1234 / DID 0x1002, BAR0 64-bit prefetch 256KB -> rxm_bar0
#   onchip_ram -- 256KB 片内 RAM (256-bit), 挂在 rxm_bar0 下, 即 BAR0 窗口
#   rst_release-- Stratix 10 复位释放, 驱动 pcie.ninit_done
#
#   注: 本 IP 也支持硬核总线主控 DMA (dma_enabled=1, 另出 rd/wr 数据搬运器 +
#   描述符控制器), 但那套等价于 5 Corundum 已做的引擎; 本最小实验只做 BAR 映射。
package require qsys

create_system {pcie_dma_sys}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
set_project_property HIDE_FROM_IP_CATALOG {true}

# ---- PCIe 硬核 (Avalon-MM 桥, Gen3x8) ----
add_instance pcie altera_pcie_s10_hip_avmm_bridge
set_instance_parameter_value pcie {design_environment}            {NATIVE}
set_instance_parameter_value pcie {chosen_devkit_hwtcl}           {NONE}
set_instance_parameter_value pcie {wrala_hwtcl}                   {Gen3x8, Interface - 256 bit, 250 MHz}
set_instance_parameter_value pcie {pll_refclk_freq_hwtcl}         {100 MHz}
set_instance_parameter_value pcie {pf0_pci_type0_vendor_id_hwtcl} {4660}
set_instance_parameter_value pcie {pf0_pci_type0_device_id_hwtcl} {4098}
set_instance_parameter_value pcie {pf0_bar0_type_hwtcl}           {64-bit prefetchable memory}
set_instance_parameter_value pcie {pf0_bar0_address_width_hwtcl}  {18}
set_instance_parameter_value pcie {dma_enabled_hwtcl}             {0}

# ---- 片内 RAM (BAR0 窗口, 256KB, 256-bit) ----
add_instance onchip_ram altera_avalon_onchip_memory2
set_instance_parameter_value onchip_ram {dataWidth}          {256}
set_instance_parameter_value onchip_ram {memorySize}         {262144}
set_instance_parameter_value onchip_ram {dualPort}           {0}
set_instance_parameter_value onchip_ram {singleClockOperation} {1}
set_instance_parameter_value onchip_ram {initMemContent}     {0}
set_instance_parameter_value onchip_ram {allowInSystemMemoryContentEditor} {0}

# ---- Stratix 10 复位释放 -> pcie.ninit_done ----
add_instance rst_release altera_s10_user_rst_clkgate

# ---- 时钟/复位桥 (coreclkout_hip 域, 稳妥分发给片内 RAM) ----
add_instance clk_br altera_clock_bridge
set_instance_parameter_value clk_br EXPLICIT_CLOCK_RATE {250000000.0}
add_instance rst_br altera_reset_bridge
set_instance_parameter_value rst_br SYNCHRONOUS_EDGES {deassert}
# 第二个时钟桥: 仅为把 coreclk 导出给顶层做心跳灯 (coreclkout_hip 扇出到两个 sink,
# 导出的是这个桥的输出, 不影响内部 RAM 时钟连接)
add_instance clk_br_led altera_clock_bridge
set_instance_parameter_value clk_br_led EXPLICIT_CLOCK_RATE {250000000.0}

# ---- 时钟/复位: pcie coreclkout_hip -> 桥 -> 片内 RAM ----
add_connection pcie.coreclkout_hip clk_br.in_clk
add_connection clk_br.out_clk onchip_ram.clk1
add_connection clk_br.out_clk rst_br.clk
add_connection pcie.app_nreset_status rst_br.in_reset
add_connection rst_br.out_reset onchip_ram.reset1
add_connection rst_release.ninit_done pcie.ninit_done
# coreclkout_hip 第二个扇出 -> LED 心跳桥 (仅导出, 无内部 sink)
add_connection pcie.coreclkout_hip clk_br_led.in_clk

# ---- BAR0 数据通路: rxm_bar0 -> 片内 RAM ----
add_connection pcie.rxm_bar0 onchip_ram.s1
set_connection_parameter_value pcie.rxm_bar0/onchip_ram.s1 baseAddress {0x0}

# ---- 导出: PCIe 物理接口 + 状态 ----
#   npor 是 conduit, 同时含 npor 与 pin_perst 两根信号 (顶层: npor=1'b1,
#   pin_perst=pcie_perstn 引脚)
add_interface refclk clock sink
set_interface_property refclk EXPORT_OF pcie.refclk
add_interface hip_serial conduit end
set_interface_property hip_serial EXPORT_OF pcie.hip_serial
add_interface npor conduit end
set_interface_property npor EXPORT_OF pcie.npor
# coreclk 心跳 (来自专用 LED 时钟桥, 250MHz coreclkout_hip 域)
add_interface coreclk clock source
set_interface_property coreclk EXPORT_OF clk_br_led.out_clk

save_system {pcie_dma_sys.qsys}
