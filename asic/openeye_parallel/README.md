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

On Paxos, from any directory:

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

## First Paxos pilot

The first successful run used Genus 23.14, TT 0.90 V / 25 C, a 2 ns clock,
and `ASIC_PARAMETERS="CLUSTER_ROWS=1 CLUSTER_COLUMNS=1 SERIAL=1 PARALLEL_MACS=1 TRANS_BITWIDTH_PSUM=20"`.
It completed synthesis with 20,134 mapped standard cells and 24,776.010 um²
cell area (33,760.555 um² including reported net area). The reported worst
setup path had 338 ps slack in the global interconnect estimate. These are
pilot values for the reduced one-cluster/12-PE core with SRAM storage abstracted;
they are not placed or routed results.

The run also emitted 7.13671 mW in `power_vectorless.rpt`, with 0 mW assigned
to the abstract memories. This uses vectorless default activity, so it is not a
workload power result and must not be compared to FastConv. No validated
OpenEye Xcelium SHM was available in this run, so activity-based `run_power.sh`
has not yet produced a result.
