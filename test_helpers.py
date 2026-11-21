# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

import random
from enum import Enum

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

VERBOSE = 0
STALL_INPUT = 0
STALL_OUTPUT = 0
GARBAGE_INVALID_LANES = 0


# Needs to match "rtl/config.sv"
class Mode(Enum):
    M_INVALID = 0
    M_AEAD128_ENC = 1
    M_AEAD128_DEC = 2
    M_HASH256 = 3
    M_XOF128 = 4
    M_CXOF128 = 5


# Needs to match "rtl/config.sv"
class Data(Enum):
    D_INVALID = 0
    D_NONCE = 1
    D_AD = 2
    D_MSG = 3
    D_TAG = 4
    D_HASH = 5


# Needs to match "rtl/ascon_core.sv"
class Fsm(Enum):
    INVALID = 0
    IDLE = 1
    LD_KEY = 2
    LD_NPUB = 3
    INIT = 4
    KADD_2 = 5
    ABS_AD = 6
    PAD_AD = 7
    PRO_AD = 8
    DOM_SEP = 9
    ABS_MSG = 10
    PAD_MSG = 11
    PRO_MSG = 12
    KADD_3 = 13
    FINAL = 14
    KADD_4 = 15
    SQZ_TAG = 16
    SQZ_HASH = 17
    VER_TAG = 18


def bus_bytes(dut):
    return len(dut.bdi) // 8


# Reset BDI signals
async def clear_bdi(dut):
    dut.bdi.value = 0
    dut.bdi_valid.value = 0
    dut.bdi_type.value = 0
    dut.bdi_eot.value = 0
    dut.bdi_eoi.value = 0
    dut.bdo_ready.value = 0


# Send data of specific type to dut
async def send_data(dut, data_in, bdi_type, bdo_ready, bdi_eoi):
    ccw_bytes = bus_bytes(dut)
    dlen = len(data_in)
    d = 0
    data_out = []
    while d < dlen:
        if STALL_INPUT:
            for _ in range(random.randint(1, 10)):
                await clear_bdi(dut)
                await RisingEdge(dut.clk)
        bdi = 0
        bdi_valid = 0
        for dd in range(d, min(d + ccw_bytes, dlen)):
            bdi |= data_in[dd] << 8 * (dd % ccw_bytes)
            bdi_valid |= 1 << (dd % ccw_bytes)
        if GARBAGE_INVALID_LANES:
            for lane in range(ccw_bytes):
                if not (bdi_valid & (1 << lane)):
                    bdi |= random.randint(1, 255) << (8 * lane)
        is_last = d + ccw_bytes >= dlen
        dut.bdi.value = bdi
        dut.bdi_valid.value = bdi_valid
        dut.bdi_type.value = bdi_type
        dut.bdi_eot.value = is_last
        dut.bdi_eoi.value = is_last and bdi_eoi
        dut.bdo_ready.value = bdo_ready
        if STALL_OUTPUT and bdo_ready:
            dut.bdo_ready.value = random.randint(0, 10) == 0
        await RisingEdge(dut.clk)
        if int(dut.bdi_valid.value) and int(dut.bdi_ready.value):
            if VERBOSE >= 3:
                dut._log.info(f"bdi:      {bdi:08X}")
            if int(dut.bdo_valid.value) and int(dut.bdo_ready.value) and (VERBOSE >= 3):
                dut._log.info(f"bdo:      {int(dut.bdo.value):08X}")
            bdo_val = int(dut.bdo.value)
            if bdo_ready and bdi_type == Data.D_MSG.value:
                assert int(dut.bdo_valid.value) == 1, "bdo_valid not set during ABS_MSG"
                assert int(dut.bdo_type.value) == Data.D_MSG.value, (
                    "bdo_type mismatch during ABS_MSG"
                )
                assert int(dut.bdo_eot.value) == int(is_last), (
                    "bdo_eot mismatch during ABS_MSG"
                )
                for lane in range(ccw_bytes):
                    if not (bdi_valid & (1 << lane)):
                        assert ((bdo_val >> (8 * lane)) & 0xFF) == 0, (
                            "non-zero masked byte lane in bdo during ABS_MSG"
                        )
            elif bdi_type == Data.D_MSG.value:
                assert int(dut.bdo_valid.value) == 0, (
                    "unexpected bdo_valid in hash/xof ABS_MSG"
                )
                assert int(dut.bdo_type.value) == Data.D_INVALID.value, (
                    "unexpected bdo_type in hash/xof ABS_MSG"
                )
                assert int(dut.bdo_eot.value) == 0, (
                    "unexpected bdo_eot in hash/xof ABS_MSG"
                )
                assert bdo_val == 0, "non-zero bdo in hash/xof ABS_MSG"
            bdo_bytes = bdo_val.to_bytes(ccw_bytes, byteorder="big")
            for dd in range(ccw_bytes):
                if bdi_valid & (1 << dd):
                    data_out.append(bdo_bytes[ccw_bytes - 1 - dd])
            d += ccw_bytes
    await clear_bdi(dut)
    return data_out


# Send key data to dut
async def send_key(dut, key_in):
    ccw_bytes = bus_bytes(dut)
    k = 0
    while k < 16:
        if STALL_INPUT and k > 0:
            for _ in range(random.randint(1, 5)):
                dut.key.value = 0
                dut.key_valid.value = 0
                await RisingEdge(dut.clk)
        key2 = 0
        for kk in range(k, min(k + ccw_bytes, 16)):
            key2 |= key_in[kk] << 8 * (kk % ccw_bytes)
        dut.key.value = key2
        dut.key_valid.value = 1
        await RisingEdge(dut.clk)
        if int(dut.key_ready.value):
            if VERBOSE >= 3:
                dut._log.info(f"key:      {int(dut.key.value):08X}")
            k += ccw_bytes
    dut.key.value = 0
    dut.key_valid.value = 0


# Receive data of specific type from dut
async def receive_data(dut, type, len=16, bdo_eoo=0, check_eot=None):
    ccw_bytes = bus_bytes(dut)
    d = 0
    data_out = []
    if check_eot is None:
        check_eot = (type == Data.D_TAG.value) or (
            type == Data.D_HASH.value and (bdo_eoo or len == 32)
        )
    while d < len:
        if STALL_OUTPUT:
            for _ in range(random.randint(1, 10)):
                dut.bdo_ready.value = 0
                dut.bdo_eoo.value = 0
                await RisingEdge(dut.clk)
        is_last = d + ccw_bytes >= len
        dut.bdo_ready.value = 1
        dut.bdo_eoo.value = is_last & bdo_eoo
        await RisingEdge(dut.clk)
        if (
            int(dut.bdo_ready.value)
            and int(dut.bdo_valid.value)
            and (int(dut.bdo_type.value) == type)
        ):
            if check_eot:
                assert int(dut.bdo_eot.value) == int(is_last), (
                    f"bdo_eot mismatch in receive_data (d={d}, len={len}, "
                    f"got={int(dut.bdo_eot.value)}, exp={int(is_last)})"
                )
            if VERBOSE >= 3:
                dut._log.info(f"bdo:      {int(dut.bdo.value):08X}")
            bdo_bytes = int(dut.bdo.value).to_bytes(ccw_bytes, byteorder="big")
            for dd in range(ccw_bytes):
                data_out.append(bdo_bytes[ccw_bytes - 1 - dd])
            d += ccw_bytes
    dut.bdo_ready.value = 0
    dut.bdo_eoo.value = 0
    return data_out


# Toggle the value of one signal
async def toggle(dut, signalStr, value):
    eval(signalStr, {"dut": cocotb.top}).value = value
    await RisingEdge(dut.clk)
    eval(signalStr, {"dut": cocotb.top}).value = 0


# Log the content of multiple byte arrays
def log(dut, verbose, dashes, **kwargs):
    if verbose <= VERBOSE:
        for k, val in kwargs.items():
            dut._log.info(
                "%s %s %s",
                k,
                " " * (8 - len(k)),
                "".join(f"{x:02X}" for x in val),
            )
        if dashes:
            dut._log.info("------------------------------------------")


# Count cycles until dut reaches IDLE state.
# Deactivated if internal signals are not accessible (e.g. synthesis).
async def cycle_cnt(dut):
    try:
        while 1:
            await RisingEdge(dut.clk)
            if int(dut.fsm_q.value) != Fsm.IDLE.value:
                break
        cycles = 1
        while 1:
            await RisingEdge(dut.clk)
            if int(dut.fsm_q.value) == Fsm.IDLE.value:
                if VERBOSE >= 1:
                    dut._log.info("cycles    %d", cycles)
                return
            cycles += 1
    except AttributeError:
        if VERBOSE >= 1:
            dut._log.info("deactivated: cycle count")


# Test case fails if no top-level I/O activity occurs for max_cycles cycles.
# Uses only top-level ports so it works in both RTL and post-synthesis sims.
async def timeout(dut, max_cycles=1000):
    idle_cycles = 0
    while True:
        await RisingEdge(dut.clk)
        activity = (
            int(dut.rst.value)
            or (int(dut.mode.value) != 0)
            or (int(dut.key_valid.value) and int(dut.key_ready.value))
            or (int(dut.bdi_valid.value) and int(dut.bdi_ready.value))
            or (int(dut.bdo_valid.value) and int(dut.bdo_ready.value))
            or int(dut.auth_valid.value)
        )
        if activity:
            idle_cycles = 0
        else:
            idle_cycles += 1
        assert idle_cycles < max_cycles, (
            f"Timeout: no I/O activity for {max_cycles} cycles"
        )


# Corrupt data for decryption failure tests
def corrupt(data):
    data_corrupt = bytearray(data).copy()
    data_corrupt[random.randint(0, len(data_corrupt) - 1)] ^= random.randint(1, 255)
    return data_corrupt


async def init_dut(dut):
    if cocotb.__version__[0] == "2":
        clock = Clock(dut.clk, 1, unit="ns")
    else:
        clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    dut.mode.value = 0
    dut.key.value = 0
    dut.key_valid.value = 0
    dut.bdo_eoo.value = 0
    await clear_bdi(dut)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


def prepend_cxof_len(cstm):
    buf = bytearray(cstm)
    for _ in range(8):
        buf.insert(0, 0)
    buf[0] = (len(cstm) * 8) % 256
    buf[1] = min(((len(cstm) * 8) >> 8), 8)
    return buf


async def run_aead_enc(dut, key, npub, ad, pt, send_key_flag=True):
    adlen = len(ad)
    msglen = len(pt)
    cycle_task = cocotb.start_soon(cycle_cnt(dut))
    timeout_task = cocotb.start_soon(timeout(dut))
    try:
        cocotb.start_soon(toggle(dut, "dut.mode", Mode.M_AEAD128_ENC.value))
        if send_key_flag:
            await send_key(dut, key)
        else:
            dut.key_valid.value = 0
            await RisingEdge(dut.clk)
        await send_data(dut, npub, Data.D_NONCE.value, 0, (adlen == 0) and (msglen == 0))
        assert int(dut.auth_valid.value) == 0, "auth_valid should be 0 during enc"
        if adlen > 0:
            await send_data(dut, ad, Data.D_AD.value, 0, (msglen == 0))
        ct_hw = []
        if msglen > 0:
            ct_hw = await send_data(dut, pt, Data.D_MSG.value, 1, 1)
        tag_hw = await receive_data(dut, Data.D_TAG.value)
        await cycle_task.complete
        return bytes(ct_hw), bytes(tag_hw)
    finally:
        timeout_task.cancel()


async def run_aead_dec(dut, key, npub, ad, ct, tag, send_key_flag=True):
    adlen = len(ad)
    msglen = len(ct)
    cycle_task = cocotb.start_soon(cycle_cnt(dut))
    timeout_task = cocotb.start_soon(timeout(dut))
    try:
        cocotb.start_soon(toggle(dut, "dut.mode", Mode.M_AEAD128_DEC.value))
        if send_key_flag:
            await send_key(dut, key)
        else:
            dut.key_valid.value = 0
            await RisingEdge(dut.clk)
        await send_data(dut, npub, Data.D_NONCE.value, 0, (adlen == 0) and (msglen == 0))
        assert int(dut.auth_valid.value) == 0, "auth_valid should be 0 during dec"
        if adlen > 0:
            await send_data(dut, ad, Data.D_AD.value, 0, (msglen == 0))
        pt_hw = []
        if msglen > 0:
            pt_hw = await send_data(dut, ct, Data.D_MSG.value, 1, 1)
        await send_data(dut, tag, Data.D_TAG.value, 0, 1)
        await RisingEdge(dut.clk)
        auth_valid = int(dut.auth_valid.value)
        auth = int(dut.auth.value)
        await cycle_task.complete
        return bytes(pt_hw), auth_valid, auth
    finally:
        timeout_task.cancel()


async def run_hash(dut, msg, bdo_eoo=0):
    msglen = len(msg)
    cycle_task = cocotb.start_soon(cycle_cnt(dut))
    timeout_task = cocotb.start_soon(timeout(dut))
    try:
        cocotb.start_soon(toggle(dut, "dut.mode", Mode.M_HASH256.value))
        if msglen == 0:
            cocotb.start_soon(toggle(dut, "dut.bdi_eot", 1))
            cocotb.start_soon(toggle(dut, "dut.bdi_eoi", 1))
        await RisingEdge(dut.clk)
        if msglen > 0:
            await send_data(dut, msg, Data.D_MSG.value, 0, 1)
        else:
            await RisingEdge(dut.clk)
        assert int(dut.auth_valid.value) == 0, "auth_valid should be 0 during hash"
        hash_hw = await receive_data(
            dut, Data.D_HASH.value, 32, bdo_eoo=bdo_eoo, check_eot=True
        )
        await cycle_task.complete
        return bytes(hash_hw[:32])
    finally:
        timeout_task.cancel()


async def run_xof(dut, msg, xoflen):
    msglen = len(msg)
    cycle_task = cocotb.start_soon(cycle_cnt(dut))
    timeout_task = cocotb.start_soon(timeout(dut))
    try:
        cocotb.start_soon(toggle(dut, "dut.mode", Mode.M_XOF128.value))
        if msglen == 0:
            cocotb.start_soon(toggle(dut, "dut.bdi_eot", 1))
            cocotb.start_soon(toggle(dut, "dut.bdi_eoi", 1))
        await RisingEdge(dut.clk)
        if msglen > 0:
            await send_data(dut, msg, Data.D_MSG.value, 0, 1)
        else:
            await RisingEdge(dut.clk)
        assert int(dut.auth_valid.value) == 0, "auth_valid should be 0 during xof"
        xof_hw = await receive_data(dut, Data.D_HASH.value, xoflen, bdo_eoo=1)
        await RisingEdge(dut.clk)
        await cycle_task.complete
        return bytes(xof_hw[:xoflen])
    finally:
        timeout_task.cancel()


async def run_cxof(dut, msg, cstm, cxoflen):
    msglen = len(msg)
    cstm_wire = prepend_cxof_len(cstm)
    cycle_task = cocotb.start_soon(cycle_cnt(dut))
    timeout_task = cocotb.start_soon(timeout(dut))
    try:
        cocotb.start_soon(toggle(dut, "dut.mode", Mode.M_CXOF128.value))
        await RisingEdge(dut.clk)
        await send_data(dut, cstm_wire, Data.D_AD.value, 0, (msglen == 0))
        assert int(dut.auth_valid.value) == 0, "auth_valid should be 0 during cxof"
        if msglen > 0:
            await send_data(dut, msg, Data.D_MSG.value, 0, 1)
        cxof_hw = await receive_data(dut, Data.D_HASH.value, cxoflen, bdo_eoo=1)
        await RisingEdge(dut.clk)
        await cycle_task.complete
        return bytes(cxof_hw[:cxoflen])
    finally:
        timeout_task.cancel()
