# PCIe 100MHz 参考时钟 (HCSL, AM34)
create_clock -name pcie_refclk -period 10.000 [get_ports pcie_refclk]
derive_pll_clocks
derive_clock_uncertainty

# H.264 编码器 = iopll 50MHz (clk_100mhz), 与 PCIe(xcvr) 异步; axil_cdc 处理跨域
set_clock_groups -asynchronous -group [get_clocks {*iopll_100mhz_inst*}]
