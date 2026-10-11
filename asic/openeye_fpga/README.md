# OpenEye_FPGA logical synthesis

This Genus flow synthesizes the FPGA-facing top `OpenEye_FPGA` for the same
configuration as the official functional convolution smoke test
`test_official_conv_c2_f6_fpga`: 4×2 clusters, 3×3 PEs per cluster, 20-bit
partial sums, a 64-bit DMA and the test's `test/cocotb_fpga/regmap.yaml`.
The RTL's `OpenEye_FPGA` wrapper (DMA, control, and inter-layer buffers) is
included in the synthesis boundary. This is not a synthesis of only the
`OpenEye_Parallel` compute core.

Run on Paxos from the repository root:

```bash
asic/openeye_fpga/run_synthesis.sh
```

The flow creates the parameter headers and DMA decoder under `results/generated`
using the repo's generators, then writes the mapped database/netlist and area,
gate, timing, and vectorless-power reports under `results/`.

The three `*_generic` RAM modules are synthesis black boxes. Their storage and
access logic are excluded from standard-cell area and power. The surrounding
RAM wrappers, address/control logic, FPGA buffers, and DMA logic remain in the
design. The black boxes have no functional model and must never be used for
simulation. Account for memory macros separately in any comparison.

The constraints use TSMC28 TT 0.90 V / 25 °C and a 2 ns clock, matching the
repository's FastConv example setup. `power_vectorless.rpt` is a synthesis
estimate without workload activity, not workload power. This flow does not
perform placement or routing.
