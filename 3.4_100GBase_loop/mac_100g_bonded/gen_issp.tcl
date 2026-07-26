package require qsys
create_system {issp_mac}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance issp altera_in_system_sources_probes
set_instance_property issp AUTO_EXPORT true
set_instance_parameter_value issp source_width {8}
set_instance_parameter_value issp probe_width {32}
set_instance_parameter_value issp instance_id {MAC}
save_system ip/issp_mac.ip
