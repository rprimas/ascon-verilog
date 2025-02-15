# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

import random
from enum import Enum

from ascon import *

VERBOSE = 0
RUNS = range(5)
CCW = 32


class Mode(Enum):
    Ascon_Nop = 0
    Ascon_AEAD128_Enc = 1
    Ascon_AEAD128_Dec = 2
    Ascon_Hash256 = 3


async def clear_bdi(dut):
    dut.bdi.value = 0
    dut.bdi_valid.value = 0
    dut.bdi_type.value = 0
    dut.bdi_eot.value = 0
    dut.bdi_eoi.value = 0
    dut.bdo_ready.value = 0


async def send_data(dut, data_in, bdi_type, bdo_ready, bdi_eoi):
    dlen = len(data_in)
    d = 0
    data_out = []
    while d < dlen:
        bdi = 0
        bdi_valid = 0
        for dd in range(d, min(d + (CCW // 8), dlen)):
            bdi |= data_in[dd] << 8 * (dd % (CCW // 8))
            bdi_valid |= 1 << (dd % (CCW // 8))
        dut.bdi.value = bdi
        dut.bdi_valid.value = bdi_valid
        dut.bdi_type.value = bdi_type
        dut.bdi_eot.value = d + (CCW // 8) >= dlen
        dut.bdi_eoi.value = d + (CCW // 8) >= dlen and bdi_eoi
        dut.bdo_ready.value = bdo_ready
        await RisingEdge(dut.clk)
        if dut.bdi_ready.value:
            bdoo = int(dut.bdo.value).to_bytes((CCW // 8))
            for dd in range((CCW // 8)):
                if bdi_valid & (1 << dd):
                    data_out.append(bdoo[(CCW // 8) - 1 - dd])
            d += CCW // 8
    return data_out


async def send_key(dut, key_in):
    k = 0
    while k < 16:
        key2 = 0
        for kk in range(k, min(k + (CCW // 8), 16)):
            key2 |= key_in[kk] << 8 * (kk % (CCW // 8))
        dut.key.value = key2
        dut.key_valid.value = 1
        await RisingEdge(dut.clk)
        if dut.key_ready.value:
            k += CCW // 8
    dut.key.value = 0
    dut.key_valid.value = 0


async def receive_data(dut, type, len=16):
    data = []
    d = 0
    while d < len:
        dut.bdo_ready.value = 1
        await RisingEdge(dut.clk)
        if dut.bdo_valid and dut.bdo_type.value == type:
            for x in int(dut.bdo.value).to_bytes(CCW // 8):
                data.append(x)
            d += CCW // 8
    dut.bdo_ready.value = 0
    return data


async def toggle(dut, signalStr, value):
    eval(signalStr, locals=dict(dut=cocotb.top)).value = value
    await RisingEdge(dut.clk)
    eval(signalStr, locals=dict(dut=cocotb.top)).value = 0


def log2(dut, verbose, dash, **kwargs):
    if verbose <= VERBOSE:
        for k, val in kwargs.items():
            dut._log.info(
                "%s %s %s",
                k,
                " " * (8 - len(k)),
                "".join("{:02X}".format(x) for x in val),
            )
        if dash:
            dut._log.info("------------------------------------------")


async def cycle_cnt(dut):
    cycles = 1
    await RisingEdge(dut.clk)
    while 1:
        await RisingEdge(dut.clk)
        if int(dut.fsm.value) == int.from_bytes("IDLE".encode("ascii")):
            # await RisingEdge(dut.clk)
            dut._log.info("cycles    %d", cycles)
            return
        cycles += 1


# ,------.                                      ,--.
# |  .---',--,--,  ,---.,--.--.,--. ,--.,---. ,-'  '-.
# |  `--, |      \| .--'|  .--' \  '  /| .-. |'-.  .-'
# |  `---.|  ||  |\ `--.|  |     \   ' | '-' '  |  |
# `------'`--''--' `---'`--'   .-'  /  |  |-'   `--'
#                              `---'   `--'


@cocotb.test()
async def test_enc(dut):

    # init test
    random.seed(31415)
    mode = Mode.Ascon_AEAD128_Enc
    clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    await cocotb.start(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    key = bytearray([random.randint(0, 255) for x in range(16)])
    npub = bytearray([random.randint(0, 255) for x in range(16)])

    log2(dut, verbose=1, dash=1, key=key, npub=npub)

    for msglen in RUNS:
        for adlen in RUNS:
            dut._log.info("test      %s %d %d", mode.name, adlen, msglen)

            ad = bytearray([random.randint(0, 255) for x in range(adlen)])
            pt = bytearray([random.randint(0, 255) for x in range(msglen)])

            # compute in software
            (ct, tag) = ascon_encrypt(key, npub, ad, pt)

            log2(dut, verbose=1, dash=0, ad=ad, pt=pt, ct=ct, tag=tag)

            await cocotb.start(cycle_cnt(dut))
            await cocotb.start(toggle(dut, "dut.mode", mode.value))

            await send_key(dut, key)

            await send_data(dut, npub, 1, 0, (adlen == 0) and (msglen == 0))
            await clear_bdi(dut)

            # send ad
            if adlen > 0:
                await send_data(dut, ad, 2, 0, (msglen == 0))
                await clear_bdi(dut)

            # send pt/ct
            if msglen > 0:
                ct_hw = await send_data(dut, pt, 3, 1, 1)
                log2(dut, 1, 0, ct_hw=ct_hw)
                await clear_bdi(dut)

            # receive tag
            tag_hw = await receive_data(dut, 4)
            log2(dut, 1, 0, tag_hw=tag_hw)

            # check tag
            for i in range(16):
                assert tag_hw[i] == tag[i], "tag mismatch"

            await RisingEdge(dut.clk)

            log2(dut, 1, 1)


# ,------.                                       ,--.
# |  .-.  \  ,---.  ,---.,--.--.,--. ,--.,---. ,-'  '-.
# |  |  \  :| .-. :| .--'|  .--' \  '  /| .-. |'-.  .-'
# |  '--'  /\   --.\ `--.|  |     \   ' | '-' '  |  |
# `-------'  `----' `---'`--'   .-'  /  |  |-'   `--'
#                               `---'   `--'


@cocotb.test()
async def test_dec(dut):

    # init test
    random.seed(31415)
    mode = Mode.Ascon_AEAD128_Dec
    clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    await cocotb.start(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    key = bytearray([random.randint(0, 255) for x in range(16)])
    npub = bytearray([random.randint(0, 255) for x in range(16)])

    log2(dut, 1, 1, key=key, npub=npub)

    for msglen in RUNS:
        for adlen in RUNS:
            dut._log.info("test      %s %d %d", mode.name, adlen, msglen)

            ad = bytearray([random.randint(0, 255) for x in range(adlen)])
            pt = bytearray([random.randint(0, 255) for x in range(msglen)])

            # compute in software
            (ct, tag) = ascon_encrypt(key, npub, ad, pt)
            await RisingEdge(dut.clk)

            log2(dut, 1, 0, ad=ad, pt=pt, ct=ct, tag=tag)

            await cocotb.start(cycle_cnt(dut))
            await cocotb.start(toggle(dut, "dut.mode", mode.value))

            await send_key(dut, key)

            # send npub
            await send_data(dut, npub, 1, 0, (adlen == 0) and (msglen == 0))
            await clear_bdi(dut)

            # send ad
            if adlen > 0:
                await send_data(dut, ad, 2, 0, (msglen == 0))
                await clear_bdi(dut)

            # send pt/ct
            if msglen > 0:
                pt_hw = await send_data(dut, ct, 3, 1, 1)
                log2(dut, 1, 0, pt_hw=pt_hw)
                await clear_bdi(dut)

            # send tag
            await send_data(dut, tag, 4, 0, 1)
            await clear_bdi(dut)

            # check tag verification
            await RisingEdge(dut.clk)
            assert dut.auth.value == 1

            log2(dut, 1, 1)


# ,--.  ,--.               ,--.
# |  '--'  | ,--,--. ,---. |  ,---.
# |  .--.  |' ,-.  |(  .-' |  .-.  |
# |  |  |  |\ '-'  |.-'  `)|  | |  |
# `--'  `--' `--`--'`----' `--' `--'


@cocotb.test()
async def test_hash(dut):

    # init test
    random.seed(31415)
    mode = Mode.Ascon_Hash256
    clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    await cocotb.start(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    log2(dut, 1, 1)

    for msglen in RUNS:
        dut._log.info("test      %s %d", mode.name, msglen)

        msg = bytearray([random.randint(0, 255) for x in range(msglen)])

        # compute in software
        hash = ascon_hash(msg)

        log2(dut, 1, 0, msg=msg, hash=hash)

        await cocotb.start(cycle_cnt(dut))
        await cocotb.start(toggle(dut, "dut.mode", mode.value))

        if msglen == 0:
            await cocotb.start(toggle(dut, "dut.bdi_eot", 1))
            await cocotb.start(toggle(dut, "dut.bdi_eoi", 1))

        await RisingEdge(dut.clk)

        # send msg
        if msglen > 0:
            await send_data(dut, msg, 3, 0, 1)
        await clear_bdi(dut)

        # receive hash
        hash_hw = await receive_data(dut, 5, 32)
        log2(dut, 1, 0, hash_hw=hash_hw)
        for i in range(32):
            assert hash_hw[i] == hash[i], "hash incorrect"

        await RisingEdge(dut.clk)

        log2(dut, 1, 1)
