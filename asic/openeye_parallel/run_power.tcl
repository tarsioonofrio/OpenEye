# Genus power analysis for a mapped database and a Cadence SHM activity dump.
# SHM must come from a functionally validated simulation using real RAM models.
set FLOW_DIR [file normalize [file dirname [info script]]]
set OUT_DIR [file join $FLOW_DIR results]
if {![info exists ::env(OPENEYE_SHM)] || $::env(OPENEYE_SHM) eq ""} {
    error "Set OPENEYE_SHM to a validated Xcelium .shm directory before power analysis"
}
if {![info exists ::env(OPENEYE_DUT_INSTANCE)] || $::env(OPENEYE_DUT_INSTANCE) eq ""} {
    error "Set OPENEYE_DUT_INSTANCE to the DUT instance path inside the SHM database"
}
set DB_FILE [file join $OUT_DIR netlist OpenEye_Parallel_mapped.db]
set SHM [file normalize $::env(OPENEYE_SHM)]
if {![file exists $DB_FILE]} { error "Missing mapped database: $DB_FILE" }
if {![file exists $SHM]} { error "SHM path does not exist: $SHM" }

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
set_db interconnect_mode ple
read_db $DB_FILE
read_stimulus $SHM -dut_instance $::env(OPENEYE_DUT_INSTANCE) -start 0ns
report_power -header -unit mW -by_category > [file join $OUT_DIR reports power_activity.rpt]
exit
