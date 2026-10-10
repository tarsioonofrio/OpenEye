# This file is part of the OpenEye project.
# © Fachhochschule Dortmund – University of Applied Sciences and Arts (until 2025), Universität Duisburg-Essen (since 2025).
# SPDX-License-Identifier: SHL-2.1
# For more details, see the LICENSE file in the root directory of this project.
import sys
import math
import os
directory = (os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), os.pardir)))
sys.path.extend([directory, os.path.dirname(os.path.realpath(__file__))])
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import open_eye.test_utils_main as ptu
import open_eye.rtl_test_utils as rtl_test_utils
import open_eye.timing_parameters as tp
import open_eye.generic_test_utils as gtu
import open_eye.DRAM as DRAM
import open_eye.time_stamper as time_stamper
import open_eye.open_eye_parameters as oep
import open_eye.layer_parameters as lp
import open_eye.simple_layer_operations as slo
import open_eye.layer_execution_state as les
import open_eye.data_create as data_create
import open_eye.tflite2model as tflite2model
import open_eye.stream_dicts as strdic
from cocotb.triggers import Timer

os.environ["CLOCK_LEN"] = "10"
os.environ["CLOCK_UNIT"] = "ns"
os.environ["CLOCK_DELAY_INPUT"] = "100"
os.environ["CLOCK_DELAY_UNIT_INPUT"] = "ps"

os.environ["CLOCK_DELAY_OUTPUT"] = "100"
os.environ["CLOCK_DELAY_UNIT_OUTPUT"] = "ps"

tests_dir = os.path.abspath(os.path.dirname(__file__))
hdl_dir = (os.path.abspath(os.path.join(os.getcwd(), os.pardir, os.pardir, "hdl")))

import logging

import sys
parent_directory = (os.path.abspath(os.path.join(os.getcwd(), os.pardir)))
sys.path.insert(1, parent_directory)


logger = logging.getLogger("cocotb")

try:
    log_level = int(os.getenv("LOGGER_LEVEL"))
except:
    logger.warning("Logger Level not given. Setting to INFO.")
    log_level = logging.INFO
logger.setLevel(logging.INFO)
global status_thread, iact_thread, wght_thread, psum_thread
status_thread = []
iact_thread = []
wght_thread = []
psum_thread = []

@cocotb.test()
async def single_layer_test(dut):
    """ Test the DUT with a given DNN model.

    This function tests the DUT with a given DNN model.
    """
    # Get variables that are used for the execution of the test
    try:
        layer_mode = os.getenv("LAYER")
    except:
        logger.error("LAYER not given.")
    try:
        filters = int((os.getenv("NUM_FILTERS")))
    except:
        logger.debug("NUM_FILTERS not set")
        filters = 1

    try:
        kernelsize_x = int((os.getenv("KERNEL_SIZE_X")))
        kernelsize_y = int((os.getenv("KERNEL_SIZE_Y")))
    except:
        kernelsize_x = 1
        kernelsize_y = 1
        logger.debug("KERNEL_SIZE_X and KERNEL_SIZE_Y not set")

    try:
        inputsize = int((os.getenv("INPUT_SIZE")))
    except:
        inputsize = 1
        logger.debug("INPUT_SIZE not set")

    try:
        outputsize = int((os.getenv("OUTPUT_SIZE")))
    except:
        outputsize = 1
        logger.debug("OUTPUT_SIZE not set")

    try:
        strides = (int((os.getenv("STRIDE"))),int((os.getenv("STRIDE"))))
    except:
        strides = (1, 1)
        logger.debug("STRIDE not set")

    try:
        channels = int((os.getenv("INPUT_CHANNELS")))
    except:
        channels = 1
        logger.debug("INPUT_CHANNELS not set")


    try:
        use_random = int((os.getenv("USE_RANDOM_VALUES")))
    except:
        use_random = 1
        logger.debug("USE_RANDOM_VALUES set to one")

    try:
        sparse_iacts = int((os.getenv("USE_SPARSE_IACTS")))
    except:
        sparse_iacts = 0
        logger.debug("No sparsety for wghts set")
    try:
        sparse_wghts = int((os.getenv("USE_SPARSE_WEIGHTS")))
    except:
        sparse_wghts = 0
        logger.debug("No sparsety for wghts set")
    
    layer_es = les.LayerExecutionState()
    serial = False
    clk_cycle = int(os.environ["CLOCK_LEN"])
    clk_cycle_unit = os.environ["CLOCK_UNIT"]

    clk_delay_in = int(os.environ["CLOCK_DELAY_INPUT"])
    clk_delay_unit_in = os.environ["CLOCK_DELAY_UNIT_INPUT"]

    clk_delay_out = int(os.environ["CLOCK_DELAY_OUTPUT"])
    clk_delay_unit_out = os.environ["CLOCK_DELAY_UNIT_OUTPUT"]

    time_printer = time_stamper.time_stamper()

    ptp = tp.PortTimingParameters()
    ptp.initiate_params(clk_cycle, clk_cycle_unit, clk_delay_in, clk_delay_unit_in, clk_delay_out, clk_delay_unit_out)
    
    # Create a test model    
    gtu.select_gpu(1)

    #Here If-Condition test, wether use model or single Layer
    if(use_random):
        model = data_create.create_layer(layer_mode, filters, kernelsize_x, kernelsize_y, inputsize, inputsize, strides, channels, outputsize)
    else:
        model = tflite2model.create_model_from_tflite(use_random)
    #load_model_function

    
    # LayerParameters is needed to size DRAM buffers and load each layer's
    # weights. Build in reverse so each layer can inspect the parameters of
    # the layer that follows it, matching the FPGA testbench's convention.
    openeye_parameter = oep.get_oep(serial)
    max_layers = len(model.layers)
    layer_parameters = [0 for _ in range(max_layers)]
    for layer_number, layer in reversed(list(enumerate(model.layers))):
        layer_parameters[max_layers - layer_number - 1] = lp.LayerParameters(
            layer_parameters, layer, openeye_parameter, layer_number, max_layers
        )
    layer_parameters.reverse()

    # Create the OpenEye parameters and the DRAM given the model.
    dram = DRAM.DRAMContents(model.layers, layer_parameters)
    time_printer.timestamp("Initialized DRAM. ", logger)
    dram.write_initial_data_to_dram(
        model.layers, layer_parameters, sparse_iacts, sparse_wghts
    )
    time_printer.timestamp("DRAM Initialized. ", logger)
    if os.environ.get("OPENEYE_LOG_INPUT"):
        for c0 in range(min(4, len(dram.fmap[0]))):
            for i in range(1):
                logger.info("input fmap[0][%d][%d][0:8] = %s", c0, i,
                            list(dram.fmap[0][c0][i][:8]))

    time_printer.timestamp("OpenEye parameters set. ", logger)

    # Start the clock
    clk = Clock(dut.clk_i, ptp.clk_cycle, units=ptp.clk_cycle_unit)
    cocotb.start_soon(clk.start())
    dut._log.info("Clock is %s " + ptp.clk_cycle_unit, ptp.clk_cycle)
    # reset the DUT
    await cocotb.start_soon(rtl_test_utils.reset_all_signals(ptp, dut, openeye_parameter.SERIAL))
    time_printer.timestamp("All signals resetted. ", logger)
    if os.environ.get("OPENEYE_TRACE_IACT_HANDSHAKE", "0").lower() in {
        "1", "true", "yes", "on"
    }:
        cocotb.start_soon(rtl_test_utils.monitor_iact_handoff(ptp, dut))
        cocotb.start_soon(rtl_test_utils.monitor_pe_iact(
            ptp, dut, openeye_parameter, pe_col=0
        ))
    if os.environ.get("OPENEYE_TRACE_PE_WRITES", "0").lower() in {"1", "true", "yes", "on"}:
        cocotb.start_soon(rtl_test_utils.trace_pe_wght_writes(
            ptp, dut, openeye_parameter
        ))
    if os.environ.get("OPENEYE_TRACE_COMPUTE_SCHEDULE", "0").lower() in {
        "1", "true", "yes", "on"
    }:
        cocotb.start_soon(rtl_test_utils.trace_compute_schedule(
            ptp, dut, openeye_parameter
        ))

    if os.environ.get("OPENEYE_TRACE_CORE_IACT"):
        cocotb.start_soon(rtl_test_utils.trace_core_iact_inputs(ptp, dut))

    if os.environ.get("OPENEYE_TRACE_PE_MACS"):
        cocotb.start_soon(rtl_test_utils.trace_pe_macs(
            ptp, dut, openeye_parameter
        ))

    # Process the layers of the model one after another
    for layer_number, layer in enumerate(model.layers):
        if("Pooling" in str(layer)):
            slo.pool(dram, layer, layer_number)
        elif("Flat" in str(layer)):
            slo.flat(dram, layer, layer_number)
        else:
            layer_parameter = layer_parameters[layer_number]
            time_printer.timestamp("Layer parameters created. ", logger)
            if os.environ.get("OPENEYE_ZERO_BIAS"):
                dram.bias[layer_number] = [0 for _ in dram.bias[layer_number]]
            calculated_results = ptu.collect_results(
                layer_number, layer_parameter, dram, openeye_parameter.SERIAL
            )
            output_order = ptu.make_ref(
                openeye_parameter, layer_parameter, layer_number, dram, calculated_results
            )
            if(logging.DEBUG >= log_level):
                time_printer.timestamp("Reference data created. ", logger)

            dram_layer_content = [dram.fmap[layer_number], dram.weights[layer_number], dram.bias[layer_number]]
            time_printer.timestamp("Start creating stream. ", logger)
            stream = ptu.write_stream(
                openeye_parameter, layer_parameter, dram_layer_content,
                sparse_iacts, sparse_wghts
            )
            
            time_printer.timestamp("Streams set. ", logger)
            for layer_repetition in range(layer_parameter.needed_total_transmissions):
                layer_thread = calculate_layer(ptp, dut, stream, openeye_parameter, layer_parameter, layer_repetition, model, layer_es, dram, log_level, layer_number, layer, output_order)
                await layer_thread
            assert ptu.compare_dram_with_ref(layer_parameter, calculated_results, dram.fmap[1 + layer_number])
        slo.batchnorm_output(layer_parameters[layer_number], 512, layer_number, dram)

    assert dut.rst_ni.value == 1, "rst_ni is not 1!"

async def calculate_layer(ptp, dut, stream, oep, lp, layer_repetition, model, layer_es, dram, log_level, layer_number, layer, output_order):
    global status_thread, iact_thread, wght_thread, psum_thread
    logger.info("Send stream.")
    # A serial convolution on the bare parallel core computes one output row
    # per compute cycle, and each cycle needs its own block of activations in
    # the PEs. Send block 0 now and the others between the cycles.
    iact_stream = stream[layer_repetition][strdic.stream_parallel_dict["iact"]]
    compute_cycles = 1
    if "Conv" in str(layer) and hasattr(dut, "iact_choose_i"):
        compute_cycles = int(lp.needed_refreshes_mx[layer_repetition][0])
    block_len = len(iact_stream[0][0][0]) // max(compute_cycles, 1)
    split_iacts = (compute_cycles > 1 and block_len > 0
                   and block_len * compute_cycles == len(iact_stream[0][0][0]))

    sub_bits = oep.IACT_WOH_Bitwidth
    subs_per_word = max(1, oep.IACT_Trans_Bitwidth // sub_bits)
    words_per_write = max(1, math.ceil(lp.used_iact_per_PE / subs_per_word))

    def shifted_stream(block):
        # data_pipeline_iact alternates the start of each compute cycle's line
        # between sub-word 0 and sub-word 1 (its "uneven ending" bookkeeping),
        # which the iact_stream_constructor accounts for when it packs lines.
        # Experiment (OPENEYE_IACT_SHIFT=1, off by default): shift an odd
        # cycle's sub-words by one. It did not fix the odd cycles; the real
        # cause is that the mapper's odd blocks are one sub-word short.
        mask = (1 << sub_bits) - 1
        out = [[[list(lane) for lane in col] for col in row]
               for row in iact_stream]
        for row in out:
            for col in row:
                for lane in col:
                    for first in range(block * block_len,
                                       (block + 1) * block_len,
                                       words_per_write):
                        words = lane[first:first + words_per_write]
                        subs = []
                        for word in words:
                            subs += [(word >> (i * sub_bits)) & mask
                                     for i in range(subs_per_word)]
                        subs = [0] + subs[:-1]
                        for n in range(len(words)):
                            lane[first + n] = sum(
                                subs[n * subs_per_word + i] << (i * sub_bits)
                                for i in range(subs_per_word))
        return out

    def write_iact_block(block):
        if not split_iacts:
            return rtl_test_utils.write_iact(
                ptp, dut, iact_stream, oep, lp)
        source = (shifted_stream(block)
                  if block % 2 == 1 and os.environ.get("OPENEYE_IACT_SHIFT")
                  else iact_stream)
        return rtl_test_utils.write_iact(
            ptp, dut, source, oep, lp,
            first_position=block * block_len,
            last_position=(block + 1) * block_len)

    async def iact_refill(block):
        logger.info("iact refill block %d of %d", block, compute_cycles)
        await write_iact_block(block)
        await Timer(ptp.clk_cycle, unit=ptp.clk_cycle_unit)
        if os.environ.get("OPENEYE_TRACE_IACT_SPAD"):
            for _ in range(12):
                await Timer(ptp.clk_cycle, unit=ptp.clk_cycle_unit)
            try:
                mem = (dut.gen_x[0].gen_y[0].OpenEye_Cluster.pe_cluster
                       .gen_X[0].gen_Y[1].pe.iact_data_SPad.ram.impl.mem)
                logger.info("iact spad after block %d: %s", block,
                            [str(mem[a].value)[-8:] for a in range(12)])
            except Exception as exc:
                logger.info("iact spad unreadable (%s)", type(exc).__name__)

    status_thread = cocotb.start_soon(rtl_test_utils.send_stream(ptp, dut, stream[layer_repetition], oep, lp, layer_repetition))
    await status_thread
    # Wait for the actual three-cycle config stream and every PE's final
    # activation/weight pipeline flush before starting the first data beat.
    await rtl_test_utils.wait_for_parameter_stream_drain(ptp, dut, oep)
    if(stream[layer_repetition][strdic.stream_parallel_dict["status"]][strdic.status_dict["skipPsum"]] != 1):
        psum_thread = cocotb.start_soon(rtl_test_utils.write_bias(ptp, dut, stream[layer_repetition][strdic.stream_parallel_dict["psum"]], oep, lp))
    if (layer_repetition != 0) :
        await iact_thread
        await wght_thread
    # start the transmission of the data
    else :
        iact_thread = cocotb.start_soon(write_iact_block(0))
        wght_thread = cocotb.start_soon(rtl_test_utils.write_wght(ptp, dut, stream[layer_repetition][strdic.stream_parallel_dict["wght"]], oep, lp))
    # wait until all transmission are finished
    await iact_thread
    await wght_thread
    if(stream[layer_repetition][strdic.stream_parallel_dict["status"]][strdic.status_dict["skipPsum"]] != 1):
        await psum_thread
    # write_iact, write_wght and write_bias deassert their enables with
    # start_soon and return immediately. Let the final enabled beat drain and
    # the input pipelines commit their word counts before compute_i can clear
    # those counters.
    await Timer(ptp.clk_cycle, unit=ptp.clk_cycle_unit)
    logger.info("Stream is sent.")
    if os.environ.get("OPENEYE_TRACE_IACT_HANDSHAKE", "0").lower() in {
        "1", "true", "yes", "on"
    }:
        rtl_test_utils.trace_active_pe_input_counts(dut, lp, oep)
    # For a single-cluster-row convolution, send_enable_conv generates the
    # PSUM-controller ready pulse for each compute cycle. Start low so the
    # first cycle is advanced by that controller rather than counted early.
    if hasattr(dut, "psum_transmitted_i"):
        cocotb.start_soon(rtl_test_utils.set_input(
            ptp, dut.psum_transmitted_i,
            0 if "Conv" in str(layer) and lp.used_Y_cluster == 1 else 1
        ))
    cocotb.start_soon(rtl_test_utils.set_input(ptp, dut.compute_i, 1))
    await Timer(ptp.clk_cycle, unit=ptp.clk_cycle_unit)
    cocotb.start_soon(rtl_test_utils.set_input(ptp, dut.compute_i, 0))
    await Timer(ptp.clk_cycle, unit=ptp.clk_cycle_unit)
    if (layer_repetition != (lp.needed_total_transmissions-1)) :
        wght_thread = cocotb.start_soon(rtl_test_utils.write_wght(ptp, dut, stream[layer_repetition + 1][strdic.stream_parallel_dict["wght"]], oep, lp))
        iact_thread = cocotb.start_soon(rtl_test_utils.write_iact(ptp, dut, stream[layer_repetition + 1][strdic.stream_parallel_dict["iact"]], oep, lp))

    # The parallel top treats psum_ready_i as downstream backpressure for the
    # output stream. Keep every PSUM sink ready while collecting this layer.
    psum_ready_mask = (1 << (oep.Clusters_X * oep.Clusters_Y * oep.NUM_GLB_PSUM)) - 1
    cocotb.start_soon(rtl_test_utils.set_input(ptp, dut.psum_ready_i, psum_ready_mask))
    await Timer(ptp.clk_cycle, unit=ptp.clk_cycle_unit)
    if("Depthwise" in str(layer)):
        await rtl_test_utils.compare_stream_Dw(
            ptp, dut, layer_number, model, layer_repetition, lp,
            oep, layer_es, dram, log_level, output_order
        )
    elif("Conv" in str(layer)):
        await rtl_test_utils.compare_stream_Conv(
            ptp, dut, layer_number, layer_repetition, lp,
            oep, layer_es, dram, log_level, output_order,
            iact_refill=iact_refill if split_iacts else None
        )
    elif("Dense" in str(layer)):
        await rtl_test_utils.compare_stream_Dense(
            ptp, dut, layer_number, layer_repetition, lp,
            oep, layer_es, dram, log_level
        )
    if os.environ.get("OPENEYE_TRACE_IACT_HANDSHAKE", "0").lower() in {
        "1", "true", "yes", "on"
    }:
        # The direct-core layer can finish with incorrect values without a
        # PE stall. Report the selected lane and accepted traffic for every
        # PE row here as well as on timeout, so a clean completion still
        # exposes activation routing errors.
        rtl_test_utils.report_iact_handoff(oep)
        rtl_test_utils.report_pe_iact()
    cocotb.start_soon(rtl_test_utils.set_input(ptp, dut.psum_ready_i, 0))
    if hasattr(dut, "psum_transmitted_i"):
        cocotb.start_soon(rtl_test_utils.set_input(
            ptp, dut.psum_transmitted_i, 0
        ))
    await Timer(ptp.clk_cycle, unit=ptp.clk_cycle_unit)
