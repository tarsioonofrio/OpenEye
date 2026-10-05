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

    dump_waves = os.environ.get("OPENEYE_DUMP_WAVES", "0").lower() in {
        "1", "true", "yes", "on"
    }
    options = {
        "simulator": simulator,
        "includes": [os.path.join(os.fspath(hdl_dir), "include")],
        # OpenEye_Parallel has a COCOTB_SIM dump hook. Keep large workload
        # traces opt-in; they can grow to gigabytes on full feature maps.
        "defines": [] if dump_waves else ["NO_TRACE"],
    }
    if simulator == "verilator":
        # The legacy RTL has known width/unused warnings; keep them visible
        # without turning them into a compile stop (the native SV runners do
        # the same with -Wno-fatal).
        options["compile_args"] = ["-Wno-fatal"]
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
