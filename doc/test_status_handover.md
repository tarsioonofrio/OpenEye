# OpenEye test status handover

Follow-up: section 7 records the convolution debugging milestone and supersedes
the original snapshot for the configurations explicitly retested there.

Snapshot date: 2026-09-19. Branch main, working tree clean, HEAD b273dab.
All results below were measured in one session on macOS (Icarus Verilog, cocotb, `openeye_env`). Every claim is tagged:

- OBSERVED: seen in a run this session (log evidence).
- FROM NOTES: taken from earlier project notes (2026-09-02 to 2026-09-18), not re-verified this session.
- ASSUMED: inference, not proven. Treat as a lead only.

## 1. Summary

| Area | Status |
|---|---|
| PE, PE_simple, data pipelines, iact stream constructor | Pass |
| PE_cluster dense and GEMM | Pass |
| FPGA GEMM / Dense (gemm_layer) | Pass, 26 of 26 |
| FPGA attention (host-orchestrated) | Pass, 10 of 10 |
| PE_cluster sparse with real zeros | Fails (about 4 percent of sampled cases) |
| FPGA convolution (any layer chained to a following layer) | Fails, 38 of 38 executed |
| cocotb_parallel system tests | Fail (stale testbench) |
| Net-level tests, wrapper, raw Verilog testbenches | Not run |

Main open problem: convolution on the FPGA top level. Main workaround for GEMM-like workloads: use the FPGA serial/DMA flow (`test/cocotb_fpga`).

## 2. How to run

- Activate: `source openeye_env/bin/activate`. Run pytest from inside the suite directory.
- macOS has no `timeout` command. Use background jobs and poll logs.
- Shell is zsh: unquoted `$var` is not word-split. Use `$(cat file)` or `${=var}` when passing many test ids.
- Test ids printed by `--collect-only` are rootdir-relative. Strip the `test/<suite>/` prefix when running from inside the suite directory.
- Use `-p no:cacheprovider -o log_cli=false -rfE` for quiet runs with a failure summary.
- Wall times measured (OBSERVED): gemm_layer 12m46s, attention 7m03s, conv_const 12m30s, single_layers 58m08s, conv3x3 sample of 8 tests 47m12s, PE_cluster sample of 162 tests 3m55s.
- Sim timeout in FPGA tests is 15 ms of sim time. A timed-out test costs 30 to 50 minutes wall.
- `test/cocotb_PE_cluster/test_PE_CLUSTER.py` now defaults to 32 smoke cases plus seven historical reproducers. `--cluster-regression=matrix` selects the 2,016-case seed-0 matrix plus six additional reproducers; `--cluster-regression=extended` restores all 32,256 cases.
- `test/cocotb_PE_cluster` now collects 64 tests by default, including focused sparsity, dense, and GEMM tests. See `test/cocotb_PE_cluster/README.md` for build reuse and opt-in waveforms.
- Constant-operand and ramp probes for value bugs (FROM NOTES): env vars `OPENEYE_CONST_IACTS`, `OPENEYE_CONST_WGHTS`, `OPENEYE_RAMP_IACTS` in `test/cocotb_fpga/OpenEye_FPGA_tb.py`. Vary the constant; one value cannot separate a data-independent DUT from a degenerate reference.

## 3. What works (OBSERVED)

| Suite (directory, file) | Result | What it covers |
|---|---|---|
| `test/`: `test_dense_reference.py`, `test_layer_adapter.py` | 13 passed | Python Dense reference math, layer adapter |
| `cocotb_PE` | 3 passed | Single PE, sparse and dense |
| `cocotb_PE_simple` | 16 passed | Simplified PE |
| `cocotb_iact_stream_constructor` | 6 passed | Split-K stream construction |
| `cocotb_data_pipeline` | 15 passed, 2 xfailed | Weight and iact SPAD encoding; xfails are the known all-zero-weight-row case |
| `cocotb_PE_cluster`: GEMM, dense | 11 passed (9 + 2) | Cluster GEMM approaches, dense conv |
| `cocotb_fpga/test_gemm_layer.py` | 26 passed | Row-stationary and output-stationary, PARALLEL_MACS 1 and 2, split-K, padding (K=31, 63), shapes 4x4 to 16x16 |
| `cocotb_fpga/test_attention.py` | 10 passed | 8 software scheduler tests plus 2 FPGA end-to-end tests (NUM_HEADS 1 and 2, SEQ_LEN 4, D_MODEL 8, output stationary) |

Caveat for the FPGA passes: geometry is small (CLUSTER_ROWS=2, K and N up to 32). Larger K, more cluster rows, and non-default NUM_GLB_* values are untested for GEMM.

## 4. What does not work

### 4.1 FPGA convolution: `compare_iact_storage` mismatch

Tests affected (all OBSERVED failing):

| Test | Failed / run | Failure point |
|---|---|---|
| `cocotb_fpga/test_conv_const.py` | 14 / 14 | `compare_iact_storage` assertion (SystemExit "FAILED 1 tests") |
| `cocotb_fpga/test_single_layers.py::test_single_conv_layer` | 16 / 16 | 14 at `compare_iact_storage`, 2 at SimTimeoutError |
| `cocotb_fpga/test_conv3x3_sparse.py` (sample of 8 of 96) | 8 / 8 | 7 at `compare_iact_storage`, 1 at SimTimeoutError |

Parametrization details (OBSERVED):
- single_layers ran CLUSTER_ROWS 8, 4, 2, 1, NUM_GLB_PSUM 4 and 2, NUM_GLB_WGHT 4 and 3. All 16 fail, so the failure does not depend on those knobs.
- The 2 timeouts are CLUSTER_ROWS=1 with NUM_GLB_PSUM=2 (both NUM_GLB_WGHT values). Other CLUSTER_ROWS=1 cases fail by mismatch instead.
- conv3x3 sample timeout: `[3-4-3-2-1-4-1-32-3-3-1-8]` (CLUSTER_ROWS=2, sparse, 32x1, 4 ch, 8 filters). Same test hung in earlier notes.
- conv_const covers CONST_VALUE 1, 2, 8, CLUSTER_ROWS 1 and 2, plus NUM_GLB_IACT/INPUT_CHANNELS variants (3,1) and (1,4).

Reasons, in order of evidence:

1. The interlayer psum to iact write-back ignores the computed psums (FROM NOTES, proven 2026-09-16). Constant-operand test: reference tracks the operand value (0x0, 0x0, 0x0101010101010101 for values 1, 2, 8) while the DUT always writes `0x2020202000000000`. So PE arithmetic is not the issue; the write-back data is independent of the input. Location suspected: `SEND_PSUM_TO_IACT` in `hdl/psum_pipeline.v`, rewritten in commit 904aa49 "Fixed Interlayer transmissions". Coordinate with the author before editing.
2. CLUSTER_ROWS=1 is a separate symptom (FROM NOTES): the iact buffer is never written (reads X) and the FSM stalls in RECEIVE_PSUMS_TO_IACT / PSUM_GET_RESULTS. Consistent with the CR=1 timeouts seen this session (OBSERVED timeouts, cause ASSUMED to be the same stall).
3. Iact double-buffer half-select is dropped (FROM NOTES): `iact_buffer_addr_reg` has the same width as `iact_buffer_addr`, so `{choose_iact_buffer, ...}` truncates and ping/pong aliases. Fix is a width change to `BRANCHES_WIDTH`. Would change behaviour; may expose a write-back that targets an unread half. `compare_iact_storage` addresses the buffer without a half offset today and needs the offset if this is fixed. Relation to the failures: ASSUMED secondary.
4. The check used to always return True and hid an empty buffer (FROM NOTES, 2026-09-03). Failures are therefore real, not new regressions. The Dense-layer stall class (fsm_cycle) was fixed 2026-09-04, so conv3x3 now mostly fails on values, not on hangs (OBSERVED: 7 of 8 mismatch, 1 of 8 hang).
5. The `test_conv3x3_sparse` hang (1 of 8) is pre-existing: stream sent, no results, WAIT_FOR_RESULTS (FROM NOTES, confirmed against baseline commit 3c9aacd). Root cause unknown.

### 4.2 PE_cluster sparse mode with real zeros

Tests affected (OBSERVED):
- `cocotb_PE_cluster/test_PE_CLUSTER_sparse.py::test_pe_cluster_weight_sparsity`: 3 failed of 14, parameters `[2-40]`, `[2-50]`, `[2-60]` (weight sparsity 40, 50, 60 percent). Failure: "Outcoming Partial Sums are not equal to Calculated data".
- `test_PE_CLUSTER.py::test_pe_cluster_conv`, sample of 162: 6 failed. Ids: `[1-1-13-40-10-6-3-2]`, `[1-2-0-50-20-6-3-4]`, `[1-2-1-40-0-6-2-3]`, `[1-2-5-60-30-10-3-2]`, `[1-2-9-60-20-10-2-3]`, `[1-2-10-50-0-8-3-2]`. Id field order: SPARSITY_EN, PARALLEL_MACS, SEED, SPARSE_WGHT, SPARSE_IACT, WGHTSIZE_X, IACTSIZE_Y, IACTSIZE_X. All 6 have SPARSITY_EN=1 and SPARSE_WGHT >= 40. Both PARALLEL_MACS values appear.

Reasons:
- Sparse-with-zeros verification gap (FROM NOTES). Four root causes were fixed 2026-09-05/06: skip count not carried into the psum address base in `PE.v`, missing `for` loop around read-after-write forwarding in `PE.v`, iact sender dropping zero activations in `pe_cluster_test_utils.send_to_iact_spad`, empty weight rows not encoded in `PE_cluster_tb.generate_spad`. The sampled failure rate went from 26 of 132 to 3 of about 129 in those notes.
- Remaining known gap (FROM NOTES): an entirely zero first weight row (`WGHT_ZERO_POS="0,1,2,3,4,5"`) and entirely zero rows generally. At high weight sparsity empty rows become likely, which matches the failing region (OBSERVED: all failures at 40 percent or more). Whether every failure this session is that one case is ASSUMED, not checked.
- The same notes list 8 PE-level sparse failures that occur only at PARALLEL_MACS=2 and link them to the weight-range shortfall (section 4.4). ASSUMED related.
- Reference tools: `doc/sparse_weight_encoding.md`, unit testbench `test/cocotb_data_pipeline/` (proves the weight pipeline emits a correct SPAD image, so the defect is in how PE.v consumes it or in the encoder).

### 4.3 cocotb_parallel

Tests affected (OBSERVED, ran `test_gemm_mode.py`, `test_single_layers.py`, `test_mnist.py`): 5 failed, 1 passed.

| Test | Error |
|---|---|
| `test_single_conv_layer[0-4-1-0-0-4-32-3-3-1-8]` | `TypeError: DRAMContents.__init__() missing 1 required positional argument: 'layer_parameters'` |
| `test_depthwise_conv_layer` (2 cases), `test_fc_layer[32-32]` | same TypeError (3 occurrences seen in log) |
| `test_single_pool_layer[10-7-7-7-1]` | `ValueError: No parameter file defined for toplevel ''` in `src/open_eye/vh_file_creator.py:180` |

Reason (FROM NOTES, matches OBSERVED errors): `OpenEye_Parallel_tb.py` predates the `src/open_eye` refactor. It still calls `DRAMContents(model)`, `write_initial_data_to_dram(model, ...)`, old `LayerParameters` and `make_ref` signatures. Current signatures are documented in the note. The serial branch of `rtl_test_utils.send_stream` also drives ports that no longer exist on `OpenEye_Parallel`. The fix is a port of the TB to the pattern in `test/cocotb_fpga/OpenEye_FPGA_tb.py`, not a mechanical patch. The single passing test is `test_gemm_mode.py::test_gemm_mode_plumbing[2]` (OBSERVED; `test_mnist.py` collects no tests). Earlier notes say it failed on a real assertion (`OS mode: cluster(0,0) PE(0,0) iact_sel_w=1, expected row index 0`); it passes now, so that was fixed since.

Recommendation: do not use cocotb_parallel for system checks. Use `test/cocotb_fpga`.

### 4.4 Known-open design issues that do not show in current passing tests (FROM NOTES)

These come from the 2026-09-18 notes. Today gemm_layer passes 26 of 26 (OBSERVED), which conflicts with the notes' "random data still fails" state. The likely explanation (ASSUMED, not verified) is the later commits in git log, for example "Fix Dense activation distribution across cluster rows" (2594391), after the notes were written. Re-check before trusting either.

- Dense/FC K-split across cluster rows: cluster row 1 received the same activations as row 0 instead of the second K slice. Question for the RTL author about how `current_x`, `x_pos_in_w_cycle`, and `iact_values_per_cluster_transmit` relate for FC. See 2594391 for the fix status.
- PARALLEL_MACS=2 weight shortfall: each PE received 3 weight ranges instead of 6. `write_wght_addr_storage` methods are dead code; something else fills the SPAD. Fix status unknown; gemm passes at PARALLEL_MACS=2 today (OBSERVED).
- Psum capture used column-major indexing while writers use row-major; fixed 2026-09-18 in `psum_pipeline.v` (FROM NOTES).

## 5. Not run this session

- `cocotb_fpga`: `test_nets.py`, `test.py`, `tflite.py`, `OpenEye_FPGA_gemmpass_probe_tb.py` (probe, not a test), 88 of 96 conv3x3 parametrizations.
- `cocotb_parallel`: `test_nets.py`, `test_mobilenet.py`.
- `cocotb_wrapper` (`OpenEye_Wrapper_tb.py`, own Makefile).
- Raw Verilog testbenches: `test/PE_dense_tb.v`, `PE_sparse_tb.v`, `PE_cluster_design/PE_cluster_tb.v`, `af_cluster/af_cluster_tb.v`, plus `test/Makefile`.
- `sw_fault_injection`, `simulation`, `multiplier`, router and mux/demux testbench directories.
- 32,094 of 32,256 `test_PE_CLUSTER.py::test_pe_cluster_conv` cases.
- Net-level tests are expected to fail on the conv write-back issue (ASSUMED) or on the stale parallel TB.

## 6. Suggested next steps

1. Debug the conv write-back in `SEND_PSUM_TO_IACT` using the constant-operand recipe on `test_conv_const.py` (about 1 minute per case at CLUSTER_ROWS=2). This unblocks single_layers, conv3x3 and the net tests.
2. Then decide on the iact double-buffer width fix (section 4.1, item 3).
3. Treat CLUSTER_ROWS=1 stalls separately (RECEIVE_PSUMS_TO_IACT / PSUM_GET_RESULTS).
4. For sparse PE_cluster, encode empty weight rows fully (xfail cases in `test/cocotb_data_pipeline/` will flip when fixed).
5. Port or retire `cocotb_parallel` tests.
6. Add a fast FPGA smoke test. Nothing under 7 minutes exists; conv paths cost up to an hour.
7. Add a sampled or pytest-marked subset of `test_PE_CLUSTER.py` so CI does not need 32k cases.

## 7. Convolution milestone follow-up (2026-09-19)

The first milestone is reached on a small dense configuration:
CLUSTER_ROWS=2, CLUSTER_COLUMNS=2, NUM_GLB_IACT=1, NUM_GLB_WGHT=3,
NUM_GLB_PSUM=4, BRANCHES=1, input 8x1 with 4 channels, 3x3 kernels,
and 4 output filters. This does not establish that convolution works for
all geometries or networks.

### Root causes established during this follow-up

- OBSERVED IN SOURCE: the legacy `LAYER=Convolution` creates two layers,
  despite the constant test's former single-layer description. Added an
  explicit `Convolution_Single` model and a testbench layer-count assertion;
  kept the legacy model unchanged.
- OBSERVED IN TRACE: bias DMA words hold two tightly packed 20-bit psums,
  but the RTL shifted each incoming word by 64 bits. Biases of 1 became
  `[1, 1, 0, 16, 16, 0, 256, ...]` across RAM lanes. Fixed payload width
  and the number of beats required to fill a psum RAM row.
- OBSERVED IN TRACE: convolution readout also shifted by 64 bits, dropping
  bits from successive 20-bit psums. The Python checker incorrectly expected
  three psums per beat. Aligned readout and reference with the existing
  two-psums-per-64-bit-beat schedule: tightly packed values, high bits zero.
- OBSERVED IN SOURCE AND REGRESSION: interlayer readout used `TRANS_WORDS`
  as its cluster stride and transpose width. With eight quantizers and four
  psum lanes per cluster it selected the wrong clusters and packed unused
  lanes. The stride now uses `NUM_GLB_PSUM`; selection and packing use only
  the active lanes of one cluster.

For the four-channel constant-8 case, the first convolution now produces
513 at the horizontal edges and 769 internally (including bias 1).
The default shift by 7 gives activation bytes 4 and 6, respectively.
The activation-buffer assertion and the second layer's final output
comparison both pass. Constants 1 and 8 are both checked; the ramp regressions
also distinguish spatial positions, with 20/32-bit accumulators and 4/8
quantizer instances.

### Validation results (OBSERVED)

| Check | Result | Coverage |
|---|---|---|
| True single-layer constant controls | 2 passed | Constants 1 and 8, 20-bit psums |
| Two-layer constant controls | 2 passed | Constants 1 and 8; intermediate buffer and final output |
| Two-layer activation ramp | 4 passed | 20/32-bit psums crossed with 4/8 quantizers |
| Two-layer activation ramp with distinct channel biases | 1 passed | Bias `1 + 128*f` makes channel permutations visible after quantization |
| FPGA GEMM K=8, N=8 | 4 passed | Both dataflows crossed with PARALLEL_MACS 1/2 |
| Python model/packing and existing Dense reference tests | 11 passed | Explicit model layer counts, signed DMA packing, Dense reference math |

The nine convolution passes were measured across focused runs during this
follow-up, not a run of the entire constant-convolution suite. The four ramp
cases plus the constant-1 two-layer case took 4m47s; channel-order validation
plus the four GEMM cases took 2m05s. No full-network or hardware-board run was
performed. The implementation is split into commits for the single-layer
control, DMA packing, interlayer write-back, and this handover.

### Scope and remaining issues

- OBSERVED: the original `(NUM_GLB_IACT=3, INPUT_CHANNELS=1)` constant-8
  reproducer still fails. After repairing bias packing, its PE output stream
  contains only the bias (1), before quantization. Its data-independent
  activation result is therefore not evidence that write-back alone ignores
  otherwise correct computed psums. Debug its activation/weight delivery next.
- CLUSTER_ROWS=1, BRANCHES>1, sparse inputs/weights, other NUM_GLB_PSUM values,
  larger images, and full networks were not revalidated in this milestone.
- Per-filter quantization coefficients, offsets, and saturation are not
  covered by these uniform-scale regressions.
- `TRACE_CONV_WRITEBACK=1` enables an optional cycle trace of psum capture,
  RAM selection, quantization, and activation writes.

Focused rerun (from the repository root):

```sh
source openeye_env/bin/activate
cd test/cocotb_fpga
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 python -m pytest \
  'test_conv_const.py::test_conv_const_single_layer[2-1]' \
  'test_conv_const.py::test_conv_const_single_layer[2-8]' \
  'test_conv_const.py::test_conv_const_two_layers[iact1_ch4-2-1]' \
  'test_conv_const.py::test_conv_const_two_layers[iact1_ch4-2-8]' \
  test_conv_const.py::test_conv_ramp_writeback \
  test_conv_const.py::test_conv_channel_order \
  -q -p no:cacheprovider -o log_cli=false -rfE
```

Disabling pytest plugin autoload avoids an unrelated localhost socket opened
by pytest-rerunfailures. The convolution reference itself uses multiprocessing
IPC, so its simulations need permission to create local sockets.

## 8. Consolidated FPGA and Parallel test evidence (2026-10-11)

This section consolidates later runs discussed after the 2026-09-19 milestone.
The results below are historical evidence from different checkouts and commits;
they were not all rerun on the current local `HEAD`. Do not interpret this table
as a green regression for the current branch. The latest remote diagnostic
baseline recorded for the October convolution investigation was `12f14a3`;
the current local checkout is a different commit and has pre-existing edits.

### FPGA top (`OpenEye_FPGA`)

`OpenEye_FPGA` includes the DMA, buffers/converters, control FSMs, quantization,
pooling, and inter-layer write-back around the compute core. A pass here is
evidence for that exact full-system test/configuration, not automatically for
`OpenEye_Parallel` alone or for every convolution geometry.

| Test/run | Simulator | Result | What the result establishes |
|---|---|---|---|
| `test/cocotb_fpga/test_gemm_layer.py` | Icarus | 26/26 passed in the 2026-09 snapshot | FPGA GEMM/Dense parametrizations at the documented small array/configurations; not convolution coverage. |
| `test/cocotb_fpga/test_gemm_layer.py::test_gemm_layer[output_stationary-3-4-3-2-32-32-1]` | Icarus | 1 passed; Cocotb reported 13,890 ns | One full-system output-stationary GEMM configuration only. This is a later individual run, not a rerun of all 26 cases. |
| Focused FPGA GEMM K=8, N=8 configurations | Icarus | 4/4 passed in the 2026-09-19 milestone | Both dataflows crossed with `PARALLEL_MACS` 1 and 2. See section 7. |
| Focused convolution controls in section 7 | Icarus | 9 focused checks passed, with one distinct configuration still failing | Small dense cases covering single-layer constants, two-layer write-back, ramps/channel order; not the full FPGA convolution suite. The exact coverage is described in section 7. |
| `test/cocotb_fpga/test_conv_const.py` plus `test_conv_mixed_weights_three_axes` | Icarus 13.0 (result recorded in `test/README_TB.md`, commit `990fec3`) | `test_conv_const.py`: 35/35 passed; the three-axis mixed-weight reproducer passed | Strong evidence that the FPGA convolution datapath worked for these tested regressions after correcting kernel-row/channel weight order. This is a historical run recorded in the repository, not rerun during this handover. |
| `test/cocotb_fpga/test_single_layers.py`, 32×32 input, 3×3 kernel, `CLUSTER_ROWS=4` | Icarus 13.0 (same recorded snapshot) | Passed: C=1/F=8, C=1/F=12, C=2/F=2, C=4/F=4. Failed: C=3/F=4 (514 differences), C=3/F=1 or 3 (timeout), C=2 or 4/F=3 (X in DMA output). | Confirms successful single-layer FPGA convolution for several supported shapes, while documenting important channel/filter configurations that still failed. |
| `test_conv_const.py::test_conv_const_single_layer[1-1]` | Icarus 12.0 on Paxos | Compiled, then stalled near 0.10 ns for about five minutes; terminated | Inconclusive before functional comparison. It is neither a DUT pass nor a functional mismatch. An isolated Icarus/Cocotb smoke test passed separately. |
| Same focused FPGA convolution attempt through Xcelium shim | Xcelium | Compile/elaboration failed | Generated `dma_storage.v` had undeclared `DMA_BITWIDTH`, `TRANSMISSIONS`, and `PARAMETER_POS_*`; no functional simulation. |
| Same attempt through Verilator 5.052 | Verilator | Build failed before functional simulation | A build-directory collision occurred first; a separate build then showed missing `regmap_params.vh` and incompatible generated slice syntax in `af_cluster.v`. |
| `test_conv_const.py` + `test_conv3x3_sparse.py` | Collection only | 130 cases collected; suite not run | Case inventory only, no pass/fail evidence for those 130 cases. |

The recorded Icarus 13.0 convolution passes, the 2026-09-19 milestone, and the
later stalled Icarus 12.0 attempt are not contradictory: they used different
simulator versions, configurations, and execution contexts. The Icarus 13.0
record demonstrates successful FPGA convolution on a meaningful subset, not
universal support. The later Icarus 12.0 attempt never reached an output
comparison. The FPGA convolution suite therefore cannot be summarized as
either universally passing or universally failing.

### Parallel and lower-level cluster tests

Test location does not always identify the DUT top: `test_gemm_workload_sv.py`
is under `cocotb_parallel`, but its SystemVerilog testbench targets
`OpenEye_FPGA`. Keep it distinct from tests whose DUT is `OpenEye_Parallel`.

| Test/run | DUT top | Simulator | Result | Scope |
|---|---|---|---|---|
| `test/cocotb_parallel/test_gemm_mode.py` | `OpenEye_Parallel` | Verilator, Icarus, Xcelium | Passed on all three in prior runs (one test per simulator) | Checks GEMM/output-stationary mode selection and plumbing; not a convolution arithmetic regression. |
| `test/cocotb_parallel/test_gemm_workload_sv.py` | `OpenEye_FPGA` via SV TB | Xcelium | Passed together with `test_gemm_mode.py`; combined run reported 2 passed | Deterministic full-system GEMM workload in the SV testbench. Only the recorded configuration/run is covered. |
| `test/cocotb_parallel/test_single_layers.py` | `OpenEye_Parallel` | Xcelium | 1 passed, 4 failed in the recorded suite run | The passing case was pooling. Convolution, two depthwise-convolution cases, and FC failed; exact convolution ID: `[0-4-1-0-0-4-32-3-3-1-8]`. This run does not establish that all failures share one cause. |
| Direct `test_single_conv_layer` | `OpenEye_Parallel` | Verilator | Failed output comparison around 30,410 ns in a prior run | Functional mismatch for that case/configuration; it is not a passing convolution test. |
| Direct `test_single_conv_layer` | `OpenEye_Parallel` | Xcelium | Failed output assertion around 5,950 ns in a prior run | Functional mismatch for that case/configuration; separate from simulator compile failures on the FPGA wrapper. |
| One convolution layer, 32×32×4 input, 8 filters | `OpenEye_Parallel` | Icarus 13.0 (recorded in `test/README_TB.md`, commit `990fec3`) | Still failed; no output matched the reference | The positive Icarus 13.0 FPGA results above do not transfer to the bare Parallel core/testbench. The testbench activation schedule and core interface differ from the FPGA wrapper. |
| `test/cocotb_PE_cluster` | PE cluster, below the `OpenEye_Parallel` top | Simulator/run recorded previously | 52 passed, 12 failed | Lower-level cluster suite; failures included convolution reproducers and sparse sweeps. This must not be reported as a full `OpenEye_Parallel` or FPGA result. |
| `test/cocotb_openeye_cluster` sparse reproducer, `PARALLEL_MACS=2`, `SPARSE_WGHT=40`, `SEED=3` | `OpenEye_Cluster` reproducer | Icarus 12.0 on Paxos | Failed output comparison; RTL fix not validated | Trace localized a spurious MAC/psum divergence around a weight-range transition, but did not prove a complete root cause or repair. No broad sweep was run. |

### Reading the combined status

- **Passed:** selected FPGA GEMM cases; the September small FPGA convolution
  milestone; `test_gemm_mode.py` mode-plumbing checks; and the recorded SV GEMM
  workload. These are separate tests and tops, not proof that the convolution
  path works generally.
- **Failed functionally:** the recorded `OpenEye_Parallel` single-convolution
  case on Verilator and Xcelium, the `test_single_layers.py` convolution case,
  and the sparse `OpenEye_Cluster` reproducer. Report each with its own top,
  simulator, and configuration.
- **Failed before simulation:** the later FPGA-wrapper Xcelium and Verilator
  attempts, due to generated HDL parameters/includes/syntax. They say nothing
  about functional output correctness.
- **Inconclusive:** the later focused FPGA convolution run on Icarus 12.0,
  which compiled but did not advance meaningfully in simulation time.
- **Not run:** the complete 130-case FPGA convolution inventory and a complete
  current-commit Parallel regression. No current-commit all-green status is
  established by the historical runs in this section.

The results are historical reports from prior sessions, not fresh reruns in
this documentation update. The detailed September observations remain in the
preceding sections; use the run logs/commit of each future regression when
promoting any item to current status.

## 9. Replay of the 2026-10-10 convolution report (2026-10-11)

The report in `test/README_TB.md` was replayed on Paxos at the exact commit
`990fec323bc0494aef2e09c852b8a77fe9b36d6f`. The working branch was restored to
`main` afterward; pre-existing uncommitted diagnostic changes were restored
unchanged. No tracked RTL or test source was edited for this replay.

Icarus 13.0 was built from the official `v13_0` tag in `/tmp` because no Icarus
module was available. Cocotb 2.1 ran from the project venv. PyTorch and ONNX
were absent, so the first attempt failed before Cocotb initialized: the runner
selected system Python and raised `ModuleNotFoundError: No module named
'torch'`. Re-running with the venv first in `PATH` and the existing temporary
stubs for unused ONNX/PyTorch imports reached the actual testbench. Those
imports are unused by these randomly generated layer tests.

| Replay | Result | Notes |
|---|---|---|
| `test/cocotb_fpga/test_conv_const.py` | **35 passed** in 370.54 s | Exact checkout at `990fec3`; includes the three-axis mixed-weight reproducer. Confirms the full recorded 35-case test file on this run. |
| Single-layer 32×32 matrix from the README | **4 passed, 5 failed** | The checked-in `test_single_layers.py` fixes its decorator values, so a temporary pytest adapter outside the repository called the same test function with the README's C/F pairs. No tracked source changed. Parameters: 32×32, 3×3, stride 1, dense random operands, `CLUSTER_ROWS=4`, `NUM_GLB_IACT=3`, `NUM_GLB_PSUM=4`, `NUM_GLB_WGHT=3`. |

Matrix detail:

| Input channels | Filters | Replay result |
|---:|---:|---|
| 1 | 8 | Pass |
| 1 | 12 | Pass |
| 2 | 2 | Pass |
| 4 | 4 | Pass |
| 3 | 4 | Failed comparison against the reference; the log also reported an output/reference line-width mismatch (64 characters received versus 60 expected). The previously recorded count of 514 differing values did not reproduce exactly. |
| 3 | 1 | Failed the diagnostic stall limit at 20,000 cycles; FSM remained at main state 10, psum state 2. |
| 3 | 3 | Failed the diagnostic stall limit at 20,000 cycles; FSM remained at main state 10, psum state 2. |
| 2 | 3 | Failed: `X detected in convolution DMA output`. |
| 4 | 3 | Failed: `X detected in convolution DMA output`. |

The replay confirms the pass/fail partition in the README for these nine C/F
pairs. The C=3/F=4 failure mode/count is not an exact reproduction of the old
514-value report. The 20,000-cycle detector deliberately replaces the much
longer simulation timeout for the two stalled configurations.

## 10. Paired `C=2/F=6` convolution on FPGA and Parallel (2026-10-11)

The same one-layer geometry was run through both tops on Paxos using Icarus
12.0, 32×32 input, 3×3 kernel, stride 1, dense random operands,
`CLUSTER_ROWS=4`, and `NUM_GLB_IACT/PSUM/WGHT=3/4/3`:

| DUT top | Test path | Result | Runtime |
|---|---|---|---|
| `OpenEye_FPGA` | `test/cocotb_fpga/test_single_layers.py`, `LAYER=Convolution_Single` | **Passed**, 1 Cocotb test | 101,290 ns simulated; 37.31 s wall |
| `OpenEye_Parallel` | `test/cocotb_parallel/test_single_layers.py::test_single_conv_layer`, called directly with `C=2/F=6` | **Failed** at `compare_dram_with_ref` after completing output | 34,590 ns simulated; 30.94 s wall |

The FPGA run is recorded at
`test/.temp/historical_990fec3_C2_F6_32x32_CR4/cocotb_sim.log`; the Parallel
result XML is
`test/.temp/historical_parallel_C2_F6_32x32_CR4_icarus12/cud2jjk3_results.xml`.
Both runs used checkout `90456ea`; its `hdl/` tree matches `990fec3`, but these
are not runs from the exact `990fec3` testbench snapshot. The FPGA run set
`OPENEYE_LAYER_SEED=123`; the Parallel Cocotb process used random seed
`1791756507` (from its result XML). Therefore the geometry and hardware
configuration match, but the generated operands were not held bit-identical
between runs; each test compared its DUT output against its own reference.

This paired result confirms that the FPGA-wrapper pass does not establish a
pass for the direct `OpenEye_Parallel` test. The direct test completed and
produced outputs, but they did not match its reference. It does not by itself
locate the mismatch in the core versus the different input/collection path of
the testbench, and it does not imply that all `OpenEye_Parallel` convolution
shapes fail.
