package require qsys
create_system {e100}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance mac alt_e100s10
set_instance_property mac AUTO_EXPORT true
# 查关键可配项默认值
foreach p {SPEED_CONFIG DEVICE_TILE PHY_REFCLK TX_IOPLL_REFCLK ENABLE_ADME CL72_PRBS SYNOPT_C4_RSFEC} {
    catch { puts "P: $p = [get_instance_parameter_value mac $p]" }
}
set_instance_parameter_value mac EXAMPLE_DESIGN 1
set_instance_parameter_value mac ENABLE_ALL_ED true
save_system ip/e100.ip
puts "SAVED"
