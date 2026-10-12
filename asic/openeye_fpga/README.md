# OpenEye_FPGA logical synthesis

This Genus flow synthesizes the FPGA-facing top `OpenEye_FPGA`, including its
DMA, control, and inter-layer buffers. By default it elaborates a single
cluster with a 2×2 PE array, two activation buffers, 20-bit partial sums, a
64-bit DMA, `SERIAL=1`, `PARALLEL_MACS=2`, and the register map in
`test/cocotb_fpga/regmap.yaml`. This is not a synthesis of only the
`OpenEye_Parallel` compute core.

Run on Paxos from the repository root:

```bash
asic/openeye_fpga/run_synthesis.sh
```

The cluster count, PE-array dimensions, and MAC lanes per PE can be selected through
`CLUSTER_ROWS`, `CLUSTER_COLUMNS`, `NUM_GLB_PSUM` (PE columns), and
`NUM_GLB_WGHT` (PE rows), and `PARALLEL_MACS`. `NUM_GLB_IACT` selects
activation buffers. Results are kept in a configuration-specific subdirectory
named for its PE shape, cluster grid, and `PARALLEL_MACS`; set
`ASIC_FPGA_RESULTS_DIR` to choose a different output directory. The intended
array sweep is 6×6, 4×4, 3×3, and 2×2 PEs, with one cluster for a direct
multiplier-count comparison.

To synthesize the two functionally passing C=2/F=6 FPGA configurations with
one MAC lane per PE and two clusters, run:

```bash
PARALLEL_MACS=1 CLUSTER_ROWS=1 CLUSTER_COLUMNS=2 \
NUM_GLB_IACT=3 NUM_GLB_PSUM=4 NUM_GLB_WGHT=3 \
  asic/openeye_fpga/run_synthesis.sh

PARALLEL_MACS=1 CLUSTER_ROWS=1 CLUSTER_COLUMNS=2 \
NUM_GLB_IACT=3 NUM_GLB_PSUM=4 NUM_GLB_WGHT=4 \
  asic/openeye_fpga/run_synthesis.sh
```

These are `4 columns × 3 rows` and `4×4` PEs per cluster. The top's RTL
default is `SERIAL=1`; the functional runs also passed that value explicitly
to Icarus. The convolution workload itself is not part of logical synthesis.

The 2-input-channel, 6-filter convolution is a workload choice. It is not
encoded as a fixed layer in this logic synthesis; use the same 2×6 workload
and exact RTL configuration when generating activity for a later power run.

The flow creates the parameter headers and DMA decoder in that configuration's
`generated/` directory using the repo's generators, then writes the mapped
database/netlist and area, gate, timing, and vectorless-power reports alongside
them.

The completed synthesis results for these two configurations are summarized in
[`RESULTS_C2F6_MACS1.md`](RESULTS_C2F6_MACS1.md). The mapped Verilog netlists,
the `parameters_FPGA.vh` used for each run, and all four full Genus reports are
tracked under their configuration-specific `results/` directories. The binary
Genus `.db` databases remain on Paxos and are not tracked. To conserve space,
the Paxos results directory retains only these two official runs; older FPGA
synthesis outputs from previous sweeps were removed after these results were
collected.

The script loads the OpenEye pilot's Genus 23.14 module. Latch inference is
reported rather than treated as fatal because the current FPGA activation
constructor contains reset-only storage that Genus flags; inspect the Genus log
before treating the netlist as implementation-ready.

The three `*_generic` RAM modules are synthesis black boxes. Their storage and
access logic are excluded from standard-cell area and power. The surrounding
RAM wrappers, address/control logic, FPGA buffers, and DMA logic remain in the
design. The black boxes have no functional model and must never be used for
simulation. Account for memory macros separately in any comparison.

The constraints use TSMC28 TT 0.90 V / 25 °C and a 2 ns clock, matching the
repository's FastConv example setup. `power_vectorless.rpt` is a synthesis
estimate without workload activity, not workload power. This flow does not
perform placement or routing.

## Workload activity power

The activity run uses the same C=2/F=6, 32×32, 3×3, seed-123 dense convolution
as the official functional test, with `SERIAL=1`, one MAC per PE, and the
selected two-cluster 4×3 or 4×4 configuration. The test clock is set to 2 ns
(500 MHz), matching `constraints.sdc`; the regular Cocotb testbench defaults
to 10 ns unless its runner supplies another value.

Run each configuration from the repository root on Paxos:

```bash
ASIC_FPGA_NUM_GLB_WGHT=3 asic/openeye_fpga/run_activity.sh
ASIC_FPGA_NUM_GLB_WGHT=3 asic/openeye_fpga/run_power.sh

ASIC_FPGA_NUM_GLB_WGHT=4 asic/openeye_fpga/run_activity.sh
ASIC_FPGA_NUM_GLB_WGHT=4 asic/openeye_fpga/run_power.sh
```

`run_activity.sh` runs the Cocotb golden-output check with Xcelium and captures
the DUT hierarchy in `activity/rtl_sim/dut.shm` only for the selected case.
`run_power.sh` consumes that SHM and the matching mapped Genus database, then
writes `reports/power_activity.rpt`. The activity is RTL simulation; it is not
gate-SDF or post-route power. RAM behavior is functional in the simulation,
but RAM macros remain abstracted from the mapped database, so the report covers
the mapped standard-cell logic only. Do not interpret zero memory power in this
report as zero physical memory power. Preserve the SHM and simulator logs on
Paxos for reproduction; they are generated binary/run artifacts and are not
tracked in Git.
