package require qsys
create_system {pm}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance mac alt_e100s10
puts "=== MAC tx_serial_clk / pll interfaces ==="
foreach i [get_instance_interfaces mac] {
    if {[regexp -nocase {serial_clk|pll|tx_clk} $i]} { puts "MAC-IF: $i" }
}
