create_clock -name clk100M -period 10.000 [get_ports clk100M]
create_clock -name qsfp0_refclk -period 1.5515 [get_ports qsfp0_refclk]
set_false_path -to [get_ports LED[*]]
