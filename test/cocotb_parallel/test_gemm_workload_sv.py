# This file is part of the OpenEye project.
# SPDX-License-Identifier: SHL-2.1

"""Run a deterministic GEMM workload through the full OpenEye_FPGA SV top."""

import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


TEST_DIR = Path(__file__).resolve().parent
REPO_ROOT = TEST_DIR.parents[1]
HDL_DIR = REPO_ROOT / "hdl"
TB_FILE = TEST_DIR / "OpenEye_FPGA_gemm_workload_tb.sv"
TOPLEVEL = "OpenEye_FPGA_gemm_workload_tb"
DEFINES = ["NO_TRACE", "USE_INTERNAL_PARAMS_PE", "USE_INTERNAL_PARAMS_PE_cluster"]
CONFIG = {
    "CLUSTER_COLUMNS": "2",
    "CLUSTER_ROWS": "2",
    "NUM_GLB_IACT": "3",
    "NUM_GLB_PSUM": "4",
    "NUM_GLB_WGHT": "3",
    "PARALLEL_MACS": "2",
    "SPARSITY_EN": "0",
    "TRANS_BITWIDTH_IACT": "16",
    "TRANS_BITWIDTH_WGHT": "16",
    "QUANT_AMOUNT": "1024",
    "DATAFLOW": "output_stationary",
    "BRANCHES": "1",
    "BUFFER_WIDTH": "12",
    "RAM_CELLS": "32",
}


def _run(command, *, cwd, env=None):
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    output = result.stdout + result.stderr
    if result.returncode:
        pytest.fail(
            f"Command failed ({result.returncode}): {' '.join(map(str, command))}\n{output}"
        )
    return output


def test_full_system_gemm_workload_sv(tmp_path):
    simulator = os.environ.get("OPENEYE_SIMULATOR", "verilator").lower()
    if simulator not in {"icarus", "verilator", "xcelium"}:
        pytest.fail(f"Unsupported OPENEYE_SIMULATOR={simulator!r}")
    compiler = {"icarus": "iverilog", "verilator": "verilator", "xcelium": "xrun"}[simulator]
    if not shutil.which(compiler):
        pytest.skip(f"{compiler} is not installed or not available on PATH")

    env = os.environ.copy()
    env.update(CONFIG)
    env["PYTHONPATH"] = os.pathsep.join(
        filter(None, [str(REPO_ROOT / "src"), env.get("PYTHONPATH")])
    )
    tmp_path.mkdir(parents=True, exist_ok=True)
    _run(
        [
            sys.executable, str(TEST_DIR / "generate_gemm_workload.py"), str(tmp_path),
            "--m", os.environ.get("OPENEYE_GEMM_M", "1"),
            "--k", os.environ.get("OPENEYE_GEMM_K", "32"),
            "--n", os.environ.get("OPENEYE_GEMM_N", "32"),
        ],
        cwd=tmp_path,
        env=env,
    )

    # Generate all HDL parameters in the isolated simulator directory. The
    # project generators write shared_config.json relative to the CWD.
    setup = (
        "from open_eye import generator, vh_file_creator; "
        f"vh_file_creator.create_vh_file_from_envvars({str(tmp_path)!r}, "
        f"{str(HDL_DIR)!r}, toplevel='OpenEye_FPGA'); "
        f"generator.create_regmap_params_vh_file({str(REPO_ROOT / 'test' / 'cocotb_fpga')!r}, "
        f"{str(tmp_path)!r}, {str(tmp_path)!r}, {str(tmp_path)!r})"
    )
    _run([sys.executable, "-c", setup], cwd=tmp_path, env=env)

    sources = sorted(
        path for path in HDL_DIR.rglob("*")
        if path.suffix in {".v", ".sv"} and path.name not in {"OpenEye_FPGA.v", "dma_storage.v"}
    )
    sources.extend([HDL_DIR / "OpenEye_FPGA.v", tmp_path / "dma_storage.v"])
    include_args = [f"-I{tmp_path}"]
    xcelium_tmp = tmp_path / "xcelium_tmp"
    xcelium_tmp.mkdir(exist_ok=True)
    if simulator == "icarus":
        executable = tmp_path / "gemm_workload.vvp"
        command = [
            "iverilog", "-g2012", "-s", TOPLEVEL,
            *[f"-D{define}" for define in DEFINES], *include_args,
            "-o", str(executable), *map(str, sources), str(TB_FILE),
        ]
        _run(command, cwd=tmp_path, env=env)
        output = _run(["vvp", str(executable)], cwd=tmp_path, env=env)
    elif simulator == "verilator":
        obj_dir = tmp_path / "obj_dir"
        command = [
            "verilator", "--binary", "--timing", "-Wno-fatal",
            "--top-module", TOPLEVEL, "--Mdir", str(obj_dir),
            *[f"-D{define}" for define in DEFINES], *include_args,
            *map(str, sources), str(TB_FILE),
        ]
        _run(command, cwd=tmp_path, env=env)
        output = _run([str(obj_dir / f"V{TOPLEVEL}")], cwd=tmp_path, env=env)
    else:
        command = [
            "xrun", "-64", "-sv", "-access", "+rwc",
            "-cds_alternate_tmpdir", str(xcelium_tmp), "-top", TOPLEVEL,
            *sum((["-define", define] for define in DEFINES), []),
            "-incdir", str(tmp_path),
            *map(str, sources), str(TB_FILE),
        ]
        output = _run(command, cwd=tmp_path, env=env)

    assert "PASS: full-system GEMM" in output, output
