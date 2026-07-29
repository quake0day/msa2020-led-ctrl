# PCIe 100MHz 参考时钟 (HCSL, AM34)
create_clock -name pcie_refclk -period 10.000 [get_ports pcie_refclk]
derive_pll_clocks
derive_clock_uncertainty
