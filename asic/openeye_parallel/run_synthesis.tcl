# Genus 23.x logical synthesis of OpenEye_Parallel with SRAM logic abstracted.
set FLOW_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT [file normalize [file join $FLOW_DIR ../..]]
set HDL_DIR [file join $REPO_ROOT hdl]
set OUT_DIR [file join $FLOW_DIR results]
file mkdir [file join $OUT_DIR reports]
file mkdir [file join $OUT_DIR netlist]
set_db init_hdl_search_path [list $FLOW_DIR]

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
set_db hdl_error_on_latch true
set_db hdl_parameter_naming_style ""

# This small, explicitly parameterized array is an elaboration/synthesis pilot.
# Override via ASIC_PARAMETERS, e.g. "CLUSTER_ROWS=2 CLUSTER_COLUMNS=2".
set parameters {CLUSTER_ROWS=1 CLUSTER_COLUMNS=1 SERIAL=1 PARALLEL_MACS=1 TRANS_BITWIDTH_PSUM=20}
if {[info exists ::env(ASIC_PARAMETERS)] && $::env(ASIC_PARAMETERS) ne ""} {
    set parameters [split $::env(ASIC_PARAMETERS)]
}

set source_files [list \
    [file join $HDL_DIR OpenEye_Parallel.v] \
    [file join $HDL_DIR OpenEye_Cluster.v] \
    [file join $HDL_DIR GLB_cluster.v] \
    [file join $HDL_DIR af_cluster.v] \
    [file join $HDL_DIR delay_cluster.v] \
    [file join $HDL_DIR router_iact.v] \
    [file join $HDL_DIR router_wght.v] \
    [file join $HDL_DIR router_psum.v] \
    [file join $HDL_DIR PE_cluster.v] \
    [file join $HDL_DIR PE.v] \
    [file join $HDL_DIR adder.v] \
    [file join $HDL_DIR data_pipeline.v] \
    [file join $HDL_DIR data_pipeline_iact.v] \
    [file join $HDL_DIR multiplier.v] \
    [file join $HDL_DIR mux2.v] \
    [file join $HDL_DIR demux2.v] \
    [file join $HDL_DIR mux_iact.v] \
    [file join $HDL_DIR SPad_DP.v] \
    [file join $HDL_DIR SPad_DP_RW.v] \
    [file join $HDL_DIR SPad_SP.v] \
    [file join $HDL_DIR RST_SYNC.v] \
    [file join $HDL_DIR RAM_DP.v] \
    [file join $HDL_DIR RAM_DP_RW.v] \
    [file join $HDL_DIR RAM_SP.v] \
    [file join $FLOW_DIR memory_abstract.v]]

read_hdl -define {USE_INTERNAL_PARAMS_PE USE_INTERNAL_PARAMS_PE_cluster NO_TRACE} \
    -sv {*}$source_files
elaborate OpenEye_Parallel -parameters $parameters
init_design
syn_generic
syn_map
syn_opt

report_area > [file join $OUT_DIR reports area.rpt]
report_gates > [file join $OUT_DIR reports gates.rpt]
report_timing -max_paths 30 > [file join $OUT_DIR reports timing.rpt]
report_power -unit mW > [file join $OUT_DIR reports power_vectorless.rpt]
write_hdl > [file join $OUT_DIR netlist OpenEye_Parallel_mapped.v]
write_db [file join $OUT_DIR netlist OpenEye_Parallel_mapped.db]
exit
