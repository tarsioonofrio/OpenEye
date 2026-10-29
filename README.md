# OpenEye in TSMC 28 nm: an Eyeriss-v2-style baseline for FastConv

This fork of [OpenEye](https://github.com/Learning-Chips-Lab/OpenEye) (FH Dortmund, University of
Duisburg-Essen) adds a TSMC 28 nm ASIC synthesis and activity-power flow, so that the accelerator can be
compared with the FastConv fast-convolution cores
([FastConv_SystemVerilog](https://github.com/tarsioonofrio/FastConv_SystemVerilog)) under the same library,
corner and clock (TT, 0.90 V, 25 °C, 500 MHz). OpenEye is an open, parameterizable take on Eyeriss v2: a sparse,
row-stationary INT8 array with 20-bit partial sums.

**These results are not part of a paper.** The ISCAS 2027 FastConv paper uses SAURIA and WinoCNN as baselines;
OpenEye is an additional reference point whose numbers are still estimates (see [Limitations](#limitations)).
The two configurations that pass the official convolution test (2 input channels, 6 filters, 32×32, 3×3)
synthesize to 79 123 and 95 877 µm² of standard cells for 24 and 32 MACs, and draw 33.7 and 39.7 mW with the
workload's RTL activity.

The README of the original project (architecture, toolchain, tests) is kept as
[`README.upstream.md`](README.upstream.md).

## Layout

| Folder | Content |
|---|---|
| `asic/openeye_fpga/` | the flow used for the results: synthesis of the `OpenEye_FPGA` top (DMA, control, buffers and clusters), activity capture, power; `results/<configuration>/` holds the netlists, parameters and reports; `RESULTS_C2F6_MACS1.md` the summary |
| `asic/openeye_parallel/` | a first synthesis/power pilot of the `OpenEye_Parallel` compute core alone (one cluster, one serial MAC by default) |
| `hdl/` | OpenEye RTL (upstream, with the fork's fixes) |
| `src/open_eye/` | Python toolchain: layer mapping, DMA stream generation, reference operations |
| `test/` | cocotb and Verilog testbenches (`test/README_TB.md`) |
| `doc/` | upstream documentation plus `asic_openeye_fpga_array_sweep.md` (square-array sweep) and `test_status_handover.md` (test status) |
| `fpga/`, `yosys/`, `nextpnr/`, `dse_scripts/`, `models/`, `tflite/` | upstream FPGA, open-source synthesis, design-space and model material |

## Configurations

Both use the `OpenEye_FPGA` top with 1 × 2 clusters, `SERIAL=1`, `PARALLEL_MACS=1` (one multiplier per PE),
`NUM_GLB_IACT=3`, `NUM_GLB_PSUM=4` (PE columns), `SPARSITY_EN=1`.

| Configuration | PEs per cluster (columns × rows) | `NUM_GLB_WGHT` | PEs/MACs | Results (`asic/openeye_fpga/results/`) |
|---|---|---|---|---|
| 4×3 | 12 | 3 | 24 | `pe4x3_clusters-1x2_macs-1/` |
| 4×4 | 16 | 4 | 32 | `pe4x4_clusters-1x2_macs-1/` |

Workload: dense convolution with 2 input channels and 6 filters, 32×32 input, 3×3 kernel, seed 123
(`test/cocotb_fpga/test_single_layers.py::test_power_activity_official_conv_c2_f6_fpga`). It differs from the
FastConv/SAURIA layer (3 input and 12 output channels).

## Quick start

The committed reports can be read without any tool: `asic/openeye_fpga/RESULTS_C2F6_MACS1.md` (in Portuguese)
summarizes them, and each `results/<configuration>/reports/` holds the full Genus area, gate, timing,
vectorless-power and activity-power reports.

The functional check of a configuration (cocotb with the Python environment of `README.upstream.md`; Xcelium as
in the flow, or `OPENEYE_SIMULATOR=icarus`; not rerun while this README was written):

```bash
CLUSTER_ROWS=1 CLUSTER_COLUMNS=2 NUM_GLB_IACT=3 NUM_GLB_PSUM=4 NUM_GLB_WGHT=3 \
PARALLEL_MACS=1 SERIAL=1 SPARSITY_EN=1 OPENEYE_CLOCK_PERIOD_NS=2 PYTHONPATH=src \
  .venv/bin/python -m pytest -x -q -s \
  test/cocotb_fpga/test_single_layers.py::test_power_activity_official_conv_c2_f6_fpga
# TESTS=1 PASS=1 FAIL=0
```

The whole flow of one configuration, with the Cadence tools and the library (from the repository root, on the
EDA host):

```bash
PARALLEL_MACS=1 CLUSTER_ROWS=1 CLUSTER_COLUMNS=2 NUM_GLB_IACT=3 NUM_GLB_PSUM=4 NUM_GLB_WGHT=3 \
  asic/openeye_fpga/run_synthesis.sh                   # about 30 min
ASIC_FPGA_NUM_GLB_WGHT=3 asic/openeye_fpga/run_activity.sh   # Xcelium + cocotb, golden check, dut.shm
ASIC_FPGA_NUM_GLB_WGHT=3 asic/openeye_fpga/run_power.sh      # Genus power with the RTL activity
```

Use `NUM_GLB_WGHT=4` / `ASIC_FPGA_NUM_GLB_WGHT=4` for the 4×4 configuration.

## Requirements

| Item | Version used | Notes |
|---|---|---|
| Python, cocotb, pytest | see `README.upstream.md` | functional tests and activity capture |
| Cadence Genus | 23.14 (`cadence/ddi/231`) | synthesis and power |
| Cadence Xcelium | 23.03 | activity capture (`run_activity.sh`) |
| Icarus Verilog | | upstream tests (`test/README_TB.md`) |
| TSMC 28 nm HPC+ standard cells `tcbn28hpcplusbwp30p140` | | under NDA, not included |

## Where each number comes from

| Value | 4×3 | 4×4 | File |
|---|---|---|---|
| Standard cells | 66 505 | 81 515 | `results/<config>/reports/gates.rpt` |
| Standard-cell area (µm²) | 79 122.960 | 95 876.802 | `results/<config>/reports/area.rpt` |
| Setup slack at 2 ns | +394 ps | +394 ps | `results/<config>/reports/timing.rpt` |
| Vectorless power (mW), not workload power | 49.1846 | 58.9395 | `results/<config>/reports/power_vectorless.rpt` |
| Simulated window (cycles at 2 ns) | 18 962 | 19 346 | `RESULTS_C2F6_MACS1.md` |
| Activity power (mW), whole simulation window | 33.7181 | 39.6638 | `results/<config>/reports/power_activity.rpt` |

Paths are relative to `asic/openeye_fpga/`. The square-array sweep (2×2 to 6×6 PEs, one cluster, vectorless
power only) is in `doc/asic_openeye_fpga_array_sweep.md`.

## Changes to OpenEye

Since the fork point (`c4bd562`; the first commit of the fork is from 2026-10-03): the two ASIC flows under `asic/`; RTL fixes found while getting
the convolution test to pass on the FPGA top (`hdl/OpenEye_FPGA.v`, `PE.v`, `PE_cluster.v`, the data
pipelines, `iact_stream_constructor.v`); matching fixes in the Python mappers (`src/open_eye/`); testbench
changes (Xcelium support, SHM capture, pooling options as FPGA parameters). Each change has its own commit
(`git log --author=Onofrio`).

## Flow, step by step

### 01: synthesis (`asic/openeye_fpga/run_synthesis.sh`, `run_synthesis.tcl`)

Generates the parameter header and the DMA register decoder for the configuration (repository generators,
`test/cocotb_fpga/regmap.yaml`), then Genus maps `OpenEye_FPGA` at 2 ns, TT 0.90 V/25 °C, without placement.
The three `*_generic` RAM modules are black boxes (`memory_abstract.v`): their wrappers, address and control
logic stay in the design, the storage does not. Outputs: mapped netlist, parameters, area, gates, timing and
vectorless-power reports.

### 02: activity (`asic/openeye_fpga/run_activity.sh`)

Runs the official convolution test with Xcelium at 2 ns (the regular cocotb default is 10 ns), checks the golden
output (`TESTS=1 PASS=1 FAIL=0`) and captures the DUT activity in `activity/rtl_sim/dut.shm`.

### 03: power (`asic/openeye_fpga/run_power.sh`, `run_power.tcl`)

Genus loads the mapped database, elaborates the RTL, enables `RTLStim2Gate`, reads the RTL activity and writes
`reports/power_activity.rpt` over the whole simulation window.

## Notes

- **Activity coverage is partial.** Primary ports and flop outputs are fully annotated, but only about 32 % of
  the netlist's net drivers (64 % of the RTL net drivers); treat the activity power as an estimate.
- **The window is the whole test** (initialization, transfers, computation, readback), not only the
  convolution.
- Genus reports latches in the activation constructor (reset-only storage); inspect the log before treating a
  netlist as implementation-ready.
- Mapped databases (`.db`), SHM and simulator logs stay on the EDA host and are not versioned.

## Limitations

- RAM storage is excluded from area and power (black boxes); memory macros must be accounted for separately.
- The synthesized top includes DMA and inter-layer buffers, so it is a larger boundary than the FastConv core.
- RTL activity mapped to gates, typical corner, no SDF, no placement and routing, no clock tree.
- The workload (2 → 6 channels) and the precision (INT8) differ from the FastConv paper layer; align the
  workload, activity window and memory boundary before any quantitative comparison.

## License

OpenEye is released under the [Solderpad Hardware License v2.1](https://solderpad.org/licenses/SHL-2.1/)
(`LICENSE`); the fork does not change it. The standard-cell library is not distributed.
