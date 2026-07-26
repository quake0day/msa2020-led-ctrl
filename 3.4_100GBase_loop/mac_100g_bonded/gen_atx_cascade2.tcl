package require qsys
# MASTER (下三联组, 靠 refclk AD34, 向上级联)
create_system {macatx_m}
set_project_property DEVICE {1SG280LN2F43E2VG}
set_project_property DEVICE_FAMILY {Stratix 10}
add_instance a altera_xcvr_atx_pll_s10_htile
set_instance_property a AUTO_EXPORT true
set_instance_parameter_value a set_auto_reference_clock_frequency 644.53125
set_instance_parameter_value a primary_pll_buffer {GXT clock output buffer}
set_instance_parameter_value a enable_28G_local_atx_path 1
set_instance_parameter_value a set_output_clock_frequency 12890.625
set_instance_parameter_value a enable_28G_output_frm_abv_atx 1
save_system ip/macatx_m.ip
