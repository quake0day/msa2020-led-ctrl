package require qsys
# 100GbE MAC (无 example design, 纯 IP 实例)
create_system {e100}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance mac alt_e100s10
set_instance_property mac AUTO_EXPORT true
save_system ip/e100.ip
