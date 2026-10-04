"""Shared simulator selection for the legacy Cocotb runners."""

import os


def simulator_options(sim_build, hdl_dir, default):
    """Return cocotb-test options for the requested simulator.

    Xcelium needs SystemVerilog mode and include paths for generated parameter
    headers. Other simulators keep the options used by the existing runners.
    """
    simulator = os.environ.get("OPENEYE_SIMULATOR", default).lower()
    if simulator not in {"icarus", "verilator", "xcelium"}:
        raise ValueError(f"Unsupported OPENEYE_SIMULATOR={simulator!r}")

    options = {
        "simulator": simulator,
        "includes": [os.path.join(os.fspath(hdl_dir), "include")],
    }
    if simulator == "xcelium":
        xcelium_tmp = os.path.join(os.fspath(sim_build), "xcelium_tmp")
        os.makedirs(xcelium_tmp, exist_ok=True)
        options["compile_args"] = [
            "-sv", "-cds_alternate_tmpdir", xcelium_tmp,
        ]
        options["includes"] = [
            os.fspath(sim_build),
            os.path.join(os.fspath(hdl_dir), "include"),
            os.fspath(hdl_dir),
        ]
    return options
