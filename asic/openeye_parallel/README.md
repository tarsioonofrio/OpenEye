# Genus pilot for `OpenEye_Parallel`

This directory is an ASIC synthesis/power pilot for the compute core. It uses
the TSMC 28 nm library and Genus module `cadence/ddi/231` available on Paxos.
The default elaboration is deliberately reduced to one cluster with one serial
MAC so it finishes as a first flow check; override `ASIC_PARAMETERS` for a
different design point.

## Memory boundary

`memory_abstract.v` declares the three `*_generic` RAM modules with matching
interfaces but no storage implementation. The synthesis manifest includes the
SPad wrappers and these empty module declarations, and omits the functional
`RAM_*_generic.v` files. Genus treats the empty modules as logic abstracts, so
their storage logic is not mapped into standard cells. The RTL and its generic
RAMs are unchanged. Do not use these declarations for simulation: the mapped
database excludes SRAM implementation area and power, and SRAM macro area,
leakage, dynamic power, and access energy must be accounted for separately.

## Synthesis

On Paxos, from the repository root (or invoke the script by absolute path):

```bash
asic/openeye_parallel/run_synthesis.sh
```

The script writes reports and a mapped database under `results/`. The default
`power_vectorless.rpt` is only a synthesis estimate without workload activity;
it is not a measured workload power result.

To override the elaboration parameters:

```bash
ASIC_PARAMETERS='CLUSTER_ROWS=2 CLUSTER_COLUMNS=2 SERIAL=1 PARALLEL_MACS=1 TRANS_BITWIDTH_PSUM=20' \
  asic/openeye_parallel/run_synthesis.sh
```

## Activity-based power

`run_power.sh` requires both `OPENEYE_SHM` and `OPENEYE_DUT_INSTANCE`. The SHM
must come from a functionally validated Xcelium simulation of the same
parameterized `OpenEye_Parallel` design using the real generic RAM models, not
the abstract declarations in this directory. The instance path depends on the
simulation testbench hierarchy. For example:

```bash
OPENEYE_SHM=/path/to/validated.shm \
OPENEYE_DUT_INSTANCE=tb.dut \
  asic/openeye_parallel/run_power.sh
```

Do not compare a power result to FastConv unless both use the same library,
PVT, clock period, workload, activity window, throughput/operation count, and
memory boundary. The SDC currently uses 2 ns to match the supplied FastConv
ASIC example's 500 MHz constraint; a thesis comparison at another frequency
must update both configurations. An OpenEye full-core result also does not
match FastConv's convolution compute block until the measured block boundaries
are aligned.

## Power status

No validated OpenEye Xcelium SHM is available yet, so activity-based
`run_power.sh` has not produced a workload power result. The synthesis script
does emit `power_vectorless.rpt`; its default activity is only a diagnostic and
must not be compared to FastConv. The Paxos Python environment also lacks
`cocotb` and `cocotb_test`, which the supplied layer-level simulation imports.

The latest successful pilot run used Genus 23.14, TT 0.90 V / 25 C, a 2 ns
clock, and `ASIC_PARAMETERS="CLUSTER_ROWS=1 CLUSTER_COLUMNS=1 SERIAL=1 PARALLEL_MACS=1 TRANS_BITWIDTH_PSUM=20"`.
It mapped 20,123 standard cells with 24,778.404 um² cell area (33,759.210 um²
including reported net area). The worst setup path had 338 ps slack in Genus's
global interconnect estimate. This describes the reduced one-cluster/12-PE
core with SRAM storage abstracted; it is not placed or routed.

The same synthesis emitted 7.14441 mW vectorless power and assigned 0 mW to
the abstract memories. This is not workload power.

## FastConv comparison checkpoint

The supplied FastConv example report is for `Conv`, TT 0.90 V / 25 C, 2 ns,
and reports 0.650788 mW from one SHM frame. Its Genus log also warns that
`RTLStim2Gate` was off for RTL stimulus, which can cause incorrect annotation,
and reports undriven hierarchical pins. Treat that number as an existing report,
not a validated comparison baseline. Re-run activity translation and power in
both projects on the same validated convolution workload and operation count,
with the same memory boundary, before drawing a power conclusion.
