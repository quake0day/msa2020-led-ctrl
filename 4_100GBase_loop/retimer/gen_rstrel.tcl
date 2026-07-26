package require qsys
create_system {rstrel}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance rr altera_s10_user_rst_clkgate
set_instance_property rr AUTO_EXPORT true
save_system ip/rstrel.ip
