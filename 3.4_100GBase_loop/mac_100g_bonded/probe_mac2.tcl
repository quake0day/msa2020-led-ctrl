package require qsys
create_system {pm2}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance mac alt_e100s10
set ifs [get_instance_interfaces mac]
puts "TOTAL_IFS=[llength $ifs]"
foreach i $ifs { puts "IF>$i" }
