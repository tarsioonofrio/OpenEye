# Testbench - Compilation and Execution Guide

This guide shows how to compile and run testbenches using iverilog and the generic Makefile.

## Quick Start

```bash
# Navigate to the test directory
cd test/

# Run the default testbench (PE_tb)
make

# Run a specific testbench
make TB=my_testbench
```

## Dense/GEMM split-K regression

The FPGA Dense path splits K across cluster rows and distributes consecutive
activation pairs round-robin across the PE rows within each cluster. Cluster
columns compute different output features. For K=32, two cluster rows and three
PE rows, the ramp input `1..32` is assigned as follows:

| Cluster row | PE row 0 | PE row 1 | PE row 2 |
|---|---|---|---|
| 0 | 1, 2, 7, 8, 13, 14 | 3, 4, 9, 10, 15, 16 | 5, 6, 11, 12, 17, 18 |
| 1 | 19, 20, 25, 26, 31, 32 | 21, 22, 27, 28, 0, 0 | 23, 24, 29, 30, 0, 0 |

`fc_storage_valid_i` marks a pair on the converter input. Each converter writes
only its cluster row's pairs, with one bank per PE row. During readout it holds
each pair for two clocks, matching the PE activation pipeline, and sends exactly
the configured number of activations per PE. Padding is included in the input
stream; the PE may omit zero activations when constructing its sparse scratchpad.
Both routing modes still reduce partial K results vertically.

The full-system sweep covers K×N = 4×4, 8×8, 4×8, 8×4, 16×16 and 32×32
with both MAC widths and routing modes, plus 31×8 and 63×8 padding cases.
These are matrix dimensions; the hardware array remains two cluster columns
by two cluster rows. Dense reference dot products run in-process to avoid
starting a Python interpreter for every output; their results are independently
checked against NumPy in `test/test_dense_reference.py`.

Run from the repository root:

```bash
# Fast converter checks: bank assignment, zeros, input gaps, repeated loads,
# two K tiles, and waiting for the PE cluster to become ready.
openeye_env/bin/python3 -m pytest -q test/cocotb_iact_stream_constructor/test_fc_split_k.py

# Complete DMA-to-output checks with random operands, both MAC widths and
# routing modes, plus odd K sizes. Run serially to avoid shared runner state.
OPENEYE_MAX_PROCS=2 openeye_env/bin/python3 -m pytest -q test/cocotb_fpga/test_gemm_layer.py

# A ramp identifies input positions; constant operands alone cannot detect
# activations sent to the wrong PE.
OPENEYE_MAX_PROCS=2 OPENEYE_RAMP_IACTS=1 OPENEYE_CONST_WGHTS=1 \
  openeye_env/bin/python3 -m pytest -q test/cocotb_fpga/test_gemm_layer.py
```

These system tests exercise a single Dense input vector (M=1), rather than
batched GEMM or a complete Transformer/SSM model.

## Command Line Options

### Option 1: Using the Makefile (Recommended)

The easiest way to run any testbench:

```bash
# Compile and run default testbench (PE_tb)
make

# Compile and run a specific testbench
make TB=my_testbench

# Run and open waveform viewer
make wave TB=PE_tb

# Clean generated files
make clean TB=PE_tb

# View available options
make help
```

### Option 2: Manual iverilog Command

If you prefer to run iverilog directly for a specific testbench:

```bash
# Example for PE_tb
iverilog -g2012 -Wall -Winfloop -Wno-timescale \
  -o PE_tb.vvp \
  ../hdl/PE.v \
  ../hdl/adder.v \
  ../hdl/data_pipeline.v \
  ../hdl/multiplier.v \
  ../hdl/mux2.v \
  ../hdl/mux_iact.v \
  ../hdl/SPad_DP.v \
  ../hdl/SPad_SP.v \
  ../hdl/RAM_DP.v \
  ../hdl/RAM_SP.v \
  ../hdl/RAM_DP_generic.v \
  ../hdl/RAM_DP_RW.v \
  ../hdl/RAM_DP_RW_generic.v \
  ../hdl/RAM_SP_generic.v \
  ../hdl/data_pipeline_iact.v \
  ../hdl/data_pipeline_wght.v \
  ../hdl/SPAD_DP_RW.v \
  PE_tb.v

# Run the simulation
vvp PE_tb.vvp
```

### Option 3: Simplified One-Liner

```bash
# For PE testbench
iverilog -g2012 -o PE_tb.vvp ../hdl/*.v PE_tb.v && vvp PE_tb.vvp

# For a different testbench
iverilog -g2012 -o my_testbench.vvp ../hdl/*.v my_testbench.v && vvp my_testbench.vvp
```

## Makefile Parameters

The Makefile supports the following parameters:

- `TB` - Testbench name without .v extension (default: PE_tb)
- `SIM` - Simulator to use (default: iverilog)

Examples:
```bash
make TB=PE_tb               # Run PE testbench
make TB=my_module_tb        # Run custom testbench
make wave TB=PE_tb          # Run and view waveforms
make clean TB=PE_tb         # Clean specific testbench files
```

## Command Line Flags Explained

- `-g2012` - Use SystemVerilog-2012 standard (supports modern Verilog syntax)
- `-Wall` - Enable all warnings
- `-Winfloop` - Warn about infinite loops
- `-Wno-timescale` - Suppress timescale warnings
- `-o <file>.vvp` - Specify output file name

## Viewing Waveforms

Testbenches generate VCD (Value Change Dump) files for waveform viewing.

### Using GTKWave

```bash
# Option 1: Using Makefile (for PE_tb)
make wave

# Option 2: Using Makefile (for specific testbench)
make wave TB=my_testbench

# Option 3: Manual command
gtkwave <testbench_name>.vcd &
```

### Recommended Signals to View (Example for PE Testbench)

In GTKWave, you can add relevant signals for debugging. For the PE testbench:

**Clock & Reset:**
- `clk_i`, `rst_ni`

**Input Activations:**
- `iact_data_i`, `iact_enable_i`, `iact_ready_o`

**Weights:**
- `wght_data_i`, `wght_enable_i`, `wght_ready_o`

**Partial Sums:**
- `psum_data_i`, `psum_enable_i`, `psum_data_o`, `psum_enable_o`

**Control:**
- `compute_i`

**Internal Signals:**
- `dut.current_state_computing` - FSM state
- `dut.adder_1.sum_o`, `dut.adder_2.sum_o` - Adder outputs

## Expected Output

When a testbench runs successfully, you should see test-specific output. For example, the PE testbench shows:

```
================================================================================
PE Convolution Test
================================================================================
[Configuration and test details...]
================================================================================
Result Validation
================================================================================
PASS: Output[0] = 25 (expected 25)
*** CONVOLUTION TEST PASSED ***
================================================================================
Test Summary
================================================================================
Total Errors: 0
*** ALL TESTS PASSED ***
================================================================================
```

Refer to each testbench's specific documentation for expected output format.

## Troubleshooting

### Error: "Can't find file"

Make sure you're in the `test/` directory:
```bash
cd test/
```

### Error: "syntax error" or "module not found"

Check that all required HDL files exist:
```bash
ls -la ../hdl/*.v
ls -la <testbench_name>.v
```

### Error: "testbench file not found"

Ensure the testbench file exists and matches the TB parameter:
```bash
# If running: make TB=my_testbench
# The file should be: test/my_testbench.v
ls -la my_testbench.v
```

### Simulation Timeout

If the simulation times out, check:
1. The DUT (Device Under Test) is correctly instantiated
2. Clock is running (view in GTKWave)
3. Reset is properly released
4. Input stimulus is being applied correctly

### No Waveform File Generated

Verify the VCD dump is enabled in your testbench:
```verilog
initial begin
    $dumpfile("<testbench_name>.vcd");
    $dumpvars(0, <module_instance>);
end
```

Or if using a parameter:
```verilog
parameter CREATE_VCD = 1;
```

## File Locations

**Generic Structure:**
- **Testbench**: `test/<testbench_name>.v`
- **HDL Sources**: `hdl/*.v`
- **Makefile**: `test/Makefile`
- **VCD Output**: `test/<testbench_name>.vcd`
- **Compiled Binary**: `test/<testbench_name>.vvp`

**Example (PE Testbench):**
- **Testbench**: `test/PE_tb.v`
- **Main Module**: `hdl/PE.v`
- **VCD Output**: `test/PE_tb.vcd`
- **Compiled Binary**: `test/PE_tb.vvp`

## Advanced Usage

### Running with Custom Parameters

Most testbenches allow you to modify test parameters directly in the source file:

```verilog
// Edit your testbench file to change parameters
parameter DATA_WIDTH = 8;
parameter ADDR_WIDTH = 10;
// ... etc
```

### Adding More Test Cases

You can add additional test cases by:
1. Duplicating test sequences in the `initial` block
2. Creating task/function calls for repeated test patterns
3. Using `$readmemh` to load test vectors from files

### Creating a New Testbench

To create a new testbench that works with this Makefile:

1. Create your testbench file: `test/my_module_tb.v`
2. Include VCD dump generation:
   ```verilog
   initial begin
       $dumpfile("my_module_tb.vcd");
       $dumpvars(0, my_module_tb);
   end
   ```
3. Update the `SOURCES` variable in the Makefile if needed
4. Run with: `make TB=my_module_tb`

## Available Testbenches

Current testbenches in this directory:
- `PE_tb` - Processing Element testbench (default)
- *(Add other testbenches here as they are created)*

## Comparison: Verilog vs CocoTB

| Feature | Verilog TB | CocoTB TB |
|---------|------------|-----------|
| Language | Verilog | Python |
| Setup | Simple, direct | Requires cocotb |
| Test Cases | Manual implementation | Parametric, automated |
| Debugging | GTKWave waveforms | Python prints + waveforms |
| Complexity | Medium | High (full protocol) |
| Use Case | Basic verification | Comprehensive testing |

For comprehensive testing, consider using CocoTB testbenches where available.

## Debug switches (environment variables)

All opt-in unless noted. They exist because a bare pass/fail says nothing about
*why* a result is wrong; each one turns a mismatch into a measurement.

### FPGA top level (`test/cocotb_fpga/`)

| Variable | Effect |
|---|---|
| `OPENEYE_PROBE_FSM=1` | Log every main-FSM transition with the decoded config fields that steer it. |
| `OPENEYE_FAIL_ON_STALL=<cycles>` | Fail once neither FSM advances for that many cycles, instead of running to the 15 ms sim timeout (hours of wall clock). The report names the FSM states, the psum handshake vectors, the router modes and the per-PE iact/weight counts. Needs `OPENEYE_PROBE_FSM`. |
| `OPENEYE_ZERO_IACTS=1` | Zero layer 0's input, so every output must equal its bias alone. Separates the bias/psum path from iact and weight delivery. |
| `OPENEYE_CONST_IACTS=<v>` | Force every layer-0 activation to a constant. |
| `OPENEYE_CONST_WGHTS=<v>` | Force every weight to a constant. With both at 1 each output becomes a *count* of the products that actually accumulated - this is how "gemm is wrong" became "gemm accumulates 9 of 32 products". **Always sweep at least two values**: a single constant cannot distinguish a data-independent DUT from a degenerate reference. |
| `DUMP_CLUSTER_IACT=1` | Per cluster, count iact handshakes at three hops (`ext`, `glb`, `pe`) plus how many carried non-zero payload; per PE, the selected lane with its valid and accepted counts. This is what showed activations arriving at every cluster and only some carrying data. |
| `DUMP_PSUM_BUFFERS=1` | End-of-run dump: per-PE SPAD occupancy, psum buffers, iact path, and the reports above. |
| `OPENEYE_MAX_PROCS=<n>` | Cap the helper processes the reference calculation spawns. Without it one pytest worker started 37 processes and drove an 8-core machine to load 94; at `3` it is 7 processes and load ~12. |

### PE cluster (`test/cocotb_PE_cluster/`)

| Variable | Effect |
|---|---|
| `OPENEYE_PSUM_TERMS=1` | On a psum mismatch, print every product feeding that psum as `(weight, iact, product, pe_y)`, and flag any single term or operand mis-pairing that accounts for the difference. |
| *(always on)* | The SPAD encoder reports any zero run that does not fit its overhead field. An undecodable weight stream would make every downstream psum comparison meaningless, so this is checked before the terms are interpreted. |

## Focused regression tests

The big parametrised suites are too large to run whole (`test_PE_CLUSTER.py`
alone collects 32256 cases), so these hold everything fixed but the one axis
that matters:

| Test | Purpose | Runtime |
|---|---|---|
| `test/cocotb_PE_cluster/test_PE_CLUSTER_sparse.py` | Weight-sparsity sweep at one shape and seed. Turns the sparse failures into a monotone curve: `PARALLEL_MACS=2` passes to 30 % and fails from 40 %. | ~15 s, 14 cases |
| `test/cocotb_fpga/test_conv_const.py::test_conv_const_single_layer` | One conv layer with constant operands, so each output is a product count. Compute and read-out only, no interlayer step. | ~65 s per case, 6 cases |
| `test/cocotb_fpga/test_conv_const.py::test_conv_const_two_layers` | Two stacked conv layers (`LAYER=Convolution_Stack`): the only focused test of the interlayer psum->iact write-back, with no pooling layer in between - the MNIST net cannot separate the two. Sweeps c = 1 and 8, because 1 and 2 quantise to the same interlayer byte. | ~65 s per case, 8 cases |

### Parallel top level (`test/cocotb_parallel/`)

| Variable | Effect |
|---|---|
| `OPENEYE_TRACE_PE_MACS=1` | One `pemac` line per PE row and clock while a PE computes: activation in use, its tag (`oh`), weight address, weight index, the weight each MAC lane multiplies, the psum address and the product. Works on both tops. |
| `OPENEYE_CONV_NO_FEEDBACK=1` | Do not feed the previous compute cycle's output back as the next cycle's psum input. With the feedback each row accumulates the previous ones (output `K*(y+1)`). Experiment, off by default. |
| `OPENEYE_TRACE_IACT_SPAD=1` | After each per-cycle activation block, log the first 12 words of one PE's activation SPAD (column 0, row 1). |
| `OPENEYE_LOG_INPUT=1` | Log the first row of each of the first four input channels, to compare with the SPAD. |
| `OPENEYE_IACT_WRITE_GAP=<n>` | Drop `iact_enable` for `n` clocks after each `iact_choose` window. Experiment, off by default. |
| `OPENEYE_IACT_SHIFT=1` | Shift odd compute cycles' activation sub-words by one. Did not help; off by default. |

## Convolution status (Icarus 13.0)

Measured on Icarus 13.0 (Icarus 12.0 hangs several `cocotb_fpga` tests). Re-run
before relying on any line; the commits are in `git log`.

### Weight order (fixed)

The activation tags the hardware generates count `channel + C * kernel_row`, so
the weight address SPAD has to be laid out kernel-row-outer, channel-inner.
`3dc5c39` had put channels outermost. Patterns that vary along at most two of
channel, filter and kernel tap sum to the same value either way, which hid it.
`test_conv_mixed_weights_three_axes` (weights `(c + 4f + 16tap) % 120 + 1`) now
passes, and `test_conv_const.py` passes 35 of 35 (about 6 minutes).

### FPGA top, one conv layer 32x32, 3x3, `CLUSTER_ROWS=4`

Run `test/cocotb_fpga/test_single_layers.py` with `LAYER=Convolution_Single`.
Without it the test runs the whole MNIST net and ignores the size parameters.

| Input channels | Filters | Result |
|---|---|---|
| 1 | 8 | pass, 59 s |
| 1 | 12 | pass, 92 s |
| 2 | 2 | pass, 37 s |
| 4 | 4 | pass, 59 s |
| 3 | 4 | fail, 514 value differences, 53 s |
| 3 | 1, 3 | hang until the timeout (15 min and 50 min) |
| 2 or 4 | 3 | fail, "X detected in convolution DMA output" |

More runs (same geometry, 2 filters unless noted; `OPENEYE_PROBE_FSM=1
OPENEYE_FAIL_ON_STALL=20000` stops a hang in about two minutes instead of the
timeout):

| Input channels | Kernel | Result |
|---|---|---|
| 3 (1 filter) | 3x3 | stall in main state 10, psum state 2 |
| 3 | 2x2 | fail, 258 value differences |
| 5 | 3x3 | stall in main state 10, psum state 2 |
| 6 | 3x3 | fail, 258 value differences |

`layer_parameters.py` sets `channel_div_trans = ceil(channels / 2)`: 1 channel
and 2 channels give 1, 3 and 4 give 2, 5 and 6 give 3. 1, 2 and 4 channels
pass; 3, 5 and 6 do not, so it is not just odd totals (6 channels, 18 values,
fails with wrong values rather than a stall). The stall report's per-PE
occupancy (`iact/wght/psum`) was `8/5/0` for both 3 channels x 1 filter and
5 channels x 2 filters, although the expected counts differ (9 and 15
activation words), so that counter is not a reliable word count there.

Odd filter counts are a second, separate
problem: with 1 input channel, 3 and 5 filters fail with 130 reported
differences each (about one filter's 2 x 32 outputs; for 3 filters they are in
`f = 2`, the unpaired last filter) while 2, 6, 8 and 12 filters pass.

Larger filter counts with more than one channel also fail, and differently:

| Input channels | Filters | Result |
|---|---|---|
| 2 | 18 | fail, about every output differs (2306 log lines for 1152 outputs) |
| 6 | 6 | fail, about every output differs (770 log lines for 384 outputs); 6 channels need 18 activation values per PE and the SPAD holds 16 |
| 4 | 9 | fail, all 576 outputs differ (every `f`, 64 each; not a permutation of the reference values); `y = 31` is the only row without a difference |

For comparison 4 x 4 and 2 x 2 pass, and 1 x 12 passes. Per-PE capacity does
not explain 4 x 9 (108 weights fit in `Wghts_per_PE = 192`, 9 psums in 16, 12
activations in `Iacts_per_PE = 16`). It does explain the 6-channel failure
(18 activation values per PE) and 2 x 18 takes the "more than 16 filters"
branch in `layer_parameters.py` (16 psums per PE, extra weight transmissions),
which none of the passing cases exercise.

Neither cause is found. For the channel problem the `iact_stream_constructor`
(odd-channel handling) is the first place to look. Four channels with the
fourth all zero should give the same numbers as three, as a workaround; not
tried. For the filter problem, the unpaired filter shares a two-MAC weight word
with a padding lane; not checked.

### Parallel top, one conv layer 32x32x4, 8 filters

Still fails: the output no longer hangs (`mapped 4/128 beats` before) but no
value matches. Found so far:

1. The bare core has no `iact_stream_constructor`, so the testbench has to
   send each compute cycle its own activation block. It now sends block 0 up
   front and block `k` before cycle `k` (`send_enable_conv`, the
   `iact_refill` hook).
2. The collector fed each cycle's output back as the next cycle's psum input,
   so rows accumulated (`OPENEYE_CONV_NO_FEEDBACK=1` removes it). Whether the
   feedback is needed for other cases, such as several channel repetitions, is
   not known.
3. With that, the activation SPAD is correct in even cycles. In odd cycles the
   stream's block starts with a zero sub-word and is one sub-word short, so
   the last activation of the cycle (the last tap of the last channel) is
   wrong. The mapper seems to model the pipeline's alternating line alignment
   (`uneven_ending` in `data_pipeline_iact.v`); not confirmed.
4. With one channel, even output rows are short by exactly 1 (suspected missing
   bias in the first cycle, not confirmed) and odd rows are wrong.

Widths below 32 break the collector (`conv_fmap_index_error`), so small
variants have to keep the width at 32. A parametrisation script must match
the text of the checked-in test file, not line numbers.

## References

- Generic Makefile: `test/Makefile`
- HDL Sources: `hdl/`
- CocoTB Tests: `test/cocotb_*/` (if available)
- Project Documentation: `doc/`
