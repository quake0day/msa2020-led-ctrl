# pcie: Stratix 10 PCIe 硬核 (Avalon-MM 桥), Gen3x8 独立 .ip
#   BAR0 64-bit prefetch 256KB -> rxm_bar0 (32-bit 非突发); 无 DMA; VID 0x1234/DID 0x1002
package require -exact qsys 21.3
proc do_create_pcie {} {
	create_system pcie
	set_project_property DEVICE {1SG280LN2F43E2VG}
	set_project_property DEVICE_FAMILY {Stratix 10}
	add_instance dut altera_pcie_s10_hip_avmm_bridge
	set_instance_parameter_value dut {design_environment}            {NATIVE}
	set_instance_parameter_value dut {chosen_devkit_hwtcl}           {NONE}
	set_instance_parameter_value dut {wrala_hwtcl}                   {Gen3x8, Interface - 256 bit, 250 MHz}
	set_instance_parameter_value dut {pll_refclk_freq_hwtcl}         {100 MHz}
	set_instance_parameter_value dut {pf0_pci_type0_vendor_id_hwtcl} {4660}
	set_instance_parameter_value dut {pf0_pci_type0_device_id_hwtcl} {4098}
	set_instance_parameter_value dut {pf0_bar0_type_hwtcl}           {64-bit prefetchable memory}
	set_instance_parameter_value dut {pf0_bar0_address_width_hwtcl}  {18}
	set_instance_parameter_value dut {pf0_bar0_enable_rxm_burst_hwtcl} {0}
	set_instance_parameter_value dut {dma_enabled_hwtcl}             {0}
	set_instance_property dut AUTO_EXPORT true
	set_module_property FILE {pcie.ip}
	set_module_property NAME {pcie}
	sync_sysinfo_parameters
	save_system pcie
}
do_create_pcie
