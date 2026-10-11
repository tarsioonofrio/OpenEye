# Genus logical synthesis of the official functional-test FPGA configuration.
set FLOW_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT [file normalize [file join $FLOW_DIR ../..]]
set HDL_DIR [file join $REPO_ROOT hdl]
set GEN_DIR [file join $FLOW_DIR results generated]
set OUT_DIR [file join $FLOW_DIR results]
file mkdir [file join $OUT_DIR reports]
file mkdir [file join $OUT_DIR netlist]
set_db init_hdl_search_path [list $GEN_DIR $FLOW_DIR]

set LIB_PATH /pdk/tsmc/PDK28/PDK_TSMC28_bv/tcbn28hpcplusbwp30p140_190a/TSMCHOME/digital/Front_End
set TECH_PATH /pdk/tsmc/PDK28/PDK_TSMC28_bv/tcbn28hpcplusbwp30p140_190a/TSMCHOME/digital/Back_End
set LIB_FILE "${LIB_PATH}/timing_power_noise/NLDM/tcbn28hpcplusbwp30p140_180a/tcbn28hpcplusbwp30p140tt0p9v25c.lib"

create_library_set -name libset_tt -timing $LIB_FILE
create_opcond -name opcond_tt -voltage 0.90 -temperature 25.0
create_timing_condition -name timing_tt -opcond opcond_tt -library_sets {libset_tt}
create_rc_corner -name rc_typ -temperature 25.0 \
    -qrc_tech "${TECH_PATH}/qrc/RC_QRC_crn28hpc+_1p09m+ut-alrdl_5x1y1z1u_typical/qrcTechFile"
create_delay_corner -name delay_tt -timing_condition timing_tt -rc_corner rc_typ
create_constraint_mode -name constraints -sdc_files [file join $FLOW_DIR constraints.sdc]
create_analysis_view -name view_tt -constraint_mode constraints -delay_corner delay_tt
set_analysis_view -setup {view_tt} -hold {view_tt}
read_physical -lefs "${TECH_PATH}/lef/tsmcn28_9lm5X1Y1Z1UUTRDL.tlef ${TECH_PATH}/lef/tcbn28hpcplusbwp30p140_110a/lef/tcbn28hpcplusbwp30p140.lef"

set_db interconnect_mode ple
# This FPGA wrapper currently infers reset-only latches in the activation
# constructor; allow Genus to map them and retain the warnings for review.
set_db hdl_error_on_latch false
set_db hdl_parameter_naming_style ""
set_db hdl_enable_real_support true

set source_files [glob -nocomplain [file join $HDL_DIR *.v] [file join $HDL_DIR *.sv]]
set filtered_sources [list]
foreach source $source_files {
    set base [file tail $source]
    if {$base in {RAM_SP_generic.v RAM_DP_generic.v RAM_DP_RW_generic.v dma_storage.v}} {
        continue
    }
    lappend filtered_sources $source
}
lappend filtered_sources [file join $FLOW_DIR memory_abstract.v]
lappend filtered_sources [file join $GEN_DIR dma_storage.v]

read_hdl -language sv \
    -define USE_INTERNAL_PARAMS_PE \
    -define USE_INTERNAL_PARAMS_PE_cluster \
    -define NO_TRACE \
    -define SYNTHESIS \
    {*}$filtered_sources
elaborate OpenEye_FPGA
init_design
syn_generic
syn_map
syn_opt

report_area > [file join $OUT_DIR reports area.rpt]
report_gates > [file join $OUT_DIR reports gates.rpt]
report_timing -max_paths 30 > [file join $OUT_DIR reports timing.rpt]
report_power -unit mW > [file join $OUT_DIR reports power_vectorless.rpt]
write_hdl > [file join $OUT_DIR netlist OpenEye_FPGA_mapped.v]
write_db [file join $OUT_DIR netlist OpenEye_FPGA_mapped.db]
exit
