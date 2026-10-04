# This file is part of the OpenEye project.
# © Fachhochschule Dortmund – University of Applied Sciences and Arts (until 2025),
# Universität Duisburg-Essen (since 2025).
# SPDX-License-Identifier: SHL-2.1

"""Compile and run the native SystemVerilog OpenEye_Parallel GEMM testbench.

Select a simulator with ``OPENEYE_SIMULATOR=icarus|verilator|xcelium``.
"""

import os
from pathlib import Path
import shutil
import subprocess

import pytest


TEST_DIR = Path(__file__).resolve().parent
REPO_ROOT = TEST_DIR.parents[1]
HDL_DIR = REPO_ROOT / "hdl"
TB_FILE = TEST_DIR / "OpenEye_Parallel_gemm_tb.sv"
TOPLEVEL = "OpenEye_Parallel_gemm_tb"

DEFINES = [
    "NO_TRACE",
    "USE_INTERNAL_PARAMS_PE",
    "USE_INTERNAL_PARAMS_PE_cluster",
]


def _run(command, *, cwd):
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    output = result.stdout + result.stderr
    if result.returncode:
        pytest.fail(
            f"Command failed ({result.returncode}): {' '.join(map(str, command))}\n{output}"
        )
    return output


def test_gemm_mode_plumbing_sv(tmp_path):
    simulator = os.environ.get("OPENEYE_SIMULATOR", "icarus").lower()
    if simulator not in {"icarus", "verilator", "xcelium"}:
        pytest.fail(f"Unsupported OPENEYE_SIMULATOR={simulator!r}")

    compiler = {"icarus": "iverilog", "verilator": "verilator", "xcelium": "xrun"}[simulator]
    if not shutil.which(compiler):
        pytest.skip(f"{compiler} is not installed or not available on PATH")

    sources = sorted(
        path for path in HDL_DIR.rglob("*")
        if path.suffix in {".v", ".sv"} and path.name != "OpenEye_FPGA.v"
    )
    include_dir = HDL_DIR / "include"
    define_args = [f"-D{define}" for define in DEFINES]

    if simulator == "icarus":
        executable = tmp_path / "gemm_mode.vvp"
        compile_command = [
            "iverilog", "-g2012", "-s", TOPLEVEL,
            *define_args, f"-I{include_dir}", "-o", str(executable),
            *map(str, sources), str(TB_FILE),
        ]
        _run(compile_command, cwd=tmp_path)
        output = _run(["vvp", str(executable)], cwd=tmp_path)
    elif simulator == "verilator":
        obj_dir = tmp_path / "obj_dir"
        compile_command = [
            "verilator", "--binary", "--timing", "-Wno-fatal",
            "--top-module", TOPLEVEL, "--Mdir", str(obj_dir),
            *define_args, f"-I{include_dir}", *map(str, sources), str(TB_FILE),
        ]
        _run(compile_command, cwd=tmp_path)
        output = _run([str(obj_dir / f"V{TOPLEVEL}")], cwd=tmp_path)
    else:
        compile_command = [
            "xrun", "-64", "-sv", "-access", "+rwc", "-top", TOPLEVEL,
            *sum((["-define", define] for define in DEFINES), []),
            "-incdir", str(include_dir), *map(str, sources), str(TB_FILE),
        ]
        output = _run(compile_command, cwd=tmp_path)

    assert "PASS: OpenEye_Parallel GEMM mode plumbing" in output, output
