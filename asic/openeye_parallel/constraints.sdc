# Keep this period synchronized with the chosen FastConv comparison point.
set sdc_version 1.5
set_load_unit -femtofarads
set_time_unit -nanoseconds

set period_clock 2.0
create_clock -name clk -period $period_clock [get_ports {clk_i}]
set_false_path -from [get_ports {rst_ni}]
set_input_delay -clock clk [expr {$period_clock / 2.0}] [all_inputs]
set_output_delay -clock clk [expr {$period_clock / 2.0}] [all_outputs]
