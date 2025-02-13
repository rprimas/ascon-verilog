# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

import cocotb
from cocotb.triggers import Timer
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

import random
from enum import Enum

from ascon import *

VERBOSE = 0
RUNS = 5

class Mode(Enum):
    Ascon_Nop = 0
    Ascon_AEAD128_Enc = 1
    Ascon_AEAD128_Dec = 2
    Ascon_Hash256 = 3


async def clear_bdi(dut):
    dut.bdi.value = 0
    dut.bdi_valid.value = 0
    dut.bdi_valid_bytes.value = 0
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
        bdi_valid_bytes = 0
        for dd in range(d, min(d + 4, dlen)):
            bdi |= data_in[dd] << 8 * (dd % 4)
            bdi_valid_bytes |= 1 << (dd % 4)
        dut.bdi.value = bdi
        dut.bdi_valid.value = 1
        dut.bdi_valid_bytes.value = bdi_valid_bytes
        dut.bdi_type.value = bdi_type
        dut.bdi_eot.value = d + 4 >= dlen
        dut.bdi_eoi.value = d + 4 >= dlen and bdi_eoi
        dut.bdo_ready.value = bdo_ready
        await RisingEdge(dut.clk)
        if dut.bdi_ready.value:  # and dut.bdo_type.value == type:
            bdoo = int(dut.bdo.value).to_bytes(4)
            for dd in range(4):
                if bdi_valid_bytes & (1 << dd):
                    data_out.append(bdoo[3 - dd])
            d += 4
    return data_out


async def receive_data(dut, type, len=16):
    data = []
    d = 0
    while d < len:
        dut.bdo_ready.value = 1
        await RisingEdge(dut.clk)
        if dut.bdo_valid and dut.bdo_type.value == type:
            for x in int(dut.bdo.value).to_bytes(4):
                data.append(x)
            d += 4
    dut.bdo_ready.value = 0
    return data


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
    clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    key = bytearray(bytes.fromhex(""))
    npub = bytearray(bytes.fromhex(""))
    for i in range(16):
        key.append(random.randint(0, 255))
        npub.append(random.randint(0, 255))

    if VERBOSE >= 1:
        dut._log.info("key       " + "".join("{:02X}".format(x) for x in key))
        dut._log.info("npub      " + "".join("{:02X}".format(x) for x in npub))
        dut._log.info("------------------------------------------")

    for msglen in range(RUNS):
        for adlen in range(RUNS):
            dut._log.info(
                "test      %s %d %d", Mode.Ascon_AEAD128_Dec.name, adlen, msglen
            )

            ad = bytearray(bytes.fromhex(""))
            for i in range(adlen):
                ad.append(random.randint(0, 255))

            pt = bytearray(bytes.fromhex(""))
            for i in range(msglen):
                pt.append(random.randint(0, 255))

            # compute in software
            (ct, tag) = ascon_encrypt(key, npub, ad, pt)

            if VERBOSE >= 1:
                dut._log.info("ad        " + "".join("{:02X}".format(x) for x in ad))
                dut._log.info("pt        " + "".join("{:02X}".format(x) for x in pt))
                dut._log.info("ct        " + "".join("{:02X}".format(x) for x in ct))
                dut._log.info("tag       " + "".join("{:02X}".format(x) for x in tag))

            # send key
            k = 0
            while k < 4:
                dut.key.value = int.from_bytes(key[4 * k : 4 * k + 4][::-1])
                dut.key_valid.value = 1
                await RisingEdge(dut.clk)
                if dut.key_ready.value:
                    k += 1
            dut.key.value = 0
            dut.key_valid.value = 0
            dut.decrypt.value = 0

            # send npub
            await send_data(dut, npub, 1, 0, (adlen == 0) and (msglen == 0))
            await clear_bdi(dut)

            # send ad
            if adlen > 0:
                await send_data(dut, ad, 2, 0, (msglen == 0))
                await clear_bdi(dut)

            # send pt/ct
            if msglen > 0:
                ct_hw = await send_data(dut, pt, 3, 1, 1)
                if VERBOSE >= 1:
                    dut._log.info(
                        "ct (hw)   " + "".join("{:02X}".format(x) for x in ct_hw)
                    )
                await clear_bdi(dut)

            # receive tag
            tag_hw = await receive_data(dut, 4)
            if VERBOSE >= 1:
                dut._log.info(
                    "tag (hw)  " + "".join("{:02X}".format(x) for x in tag_hw)
                )

            # check tag
            for i in range(16):
                assert tag_hw[i] == tag[i], "tag mismatch"

            if VERBOSE >= 1:
                dut._log.info("------------------------------------------")


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
    clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    key = bytearray(bytes.fromhex(""))
    npub = bytearray(bytes.fromhex(""))
    for i in range(16):
        key.append(random.randint(0, 255))
        npub.append(random.randint(0, 255))

    if VERBOSE >= 1:
        dut._log.info("key       " + "".join("{:02X}".format(x) for x in key))
        dut._log.info("npub      " + "".join("{:02X}".format(x) for x in npub))
        dut._log.info("------------------------------------------")

    for msglen in range(RUNS):
        for adlen in range(RUNS):
            dut._log.info(
                "test      %s %d %d", Mode.Ascon_AEAD128_Dec.name, adlen, msglen
            )

            ad = bytearray(bytes.fromhex(""))
            for i in range(adlen):
                ad.append(random.randint(0, 255))

            pt = bytearray(bytes.fromhex(""))
            for i in range(msglen):
                pt.append(random.randint(0, 255))

            # compute in software
            (ct, tag) = ascon_encrypt(key, npub, ad, pt)

            if VERBOSE >= 1:
                dut._log.info("ad        " + "".join("{:02X}".format(x) for x in ad))
                dut._log.info("pt        " + "".join("{:02X}".format(x) for x in pt))
                dut._log.info("ct        " + "".join("{:02X}".format(x) for x in ct))
                dut._log.info("tag       " + "".join("{:02X}".format(x) for x in tag))

            # send key
            k = 0
            while k < 4:
                dut.key.value = int.from_bytes(key[4 * k : 4 * k + 4][::-1])
                dut.key_valid.value = 1
                await RisingEdge(dut.clk)
                if dut.key_ready.value:
                    k += 1
            dut.key.value = 0
            dut.key_valid.value = 0
            dut.decrypt.value = 1

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
                if VERBOSE >= 1:
                    dut._log.info(
                        "pt (hw)   " + "".join("{:02X}".format(x) for x in pt_hw)
                    )
                await clear_bdi(dut)

            # send tag
            await send_data(dut, tag, 4, 0, 1)
            await clear_bdi(dut)

            # check tag verification
            await RisingEdge(dut.clk)
            assert dut.auth.value == 1
            if VERBOSE >= 1:
                dut._log.info("auth (hw) %d", dut.auth.value)

            if VERBOSE >= 1:
                dut._log.info("------------------------------------------")


# ,--.  ,--.               ,--.
# |  '--'  | ,--,--. ,---. |  ,---.
# |  .--.  |' ,-.  |(  .-' |  .-.  |
# |  |  |  |\ '-'  |.-'  `)|  | |  |
# `--'  `--' `--`--'`----' `--' `--'


@cocotb.test()
async def test_hash(dut):

    # init test
    random.seed(31415)
    clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    if VERBOSE >= 1:
        dut._log.info("------------------------------------------")

    for msglen in range(RUNS**2):
        dut._log.info("test      %s %d", Mode.Ascon_Hash256.name, msglen)

        msg = bytearray(bytes.fromhex(""))
        for i in range(msglen):
            msg.append(random.randint(0, 255))

        # compute in software
        hash = ascon_hash(msg)

        if VERBOSE >= 1:
            dut._log.info("msg       " + "".join("{:02X}".format(x) for x in msg))
            dut._log.info("hash      " + "".join("{:02X}".format(x) for x in hash))

        dut.hash.value = 1
        dut.bdi_valid.value = 1
        dut.bdi_type.value = 3
        if msglen == 0:
            dut.bdi_eoi.value = 1

        await RisingEdge(dut.clk)

        # send msg
        if msglen > 0:
            await send_data(dut, msg, 3, 0, 1)
        await clear_bdi(dut)

        # receive hash
        hash_hw = await receive_data(dut, 5, 32)
        if VERBOSE >= 1:
            dut._log.info("hash (hw) " + "".join("{:02X}".format(x) for x in hash_hw))

        # check hash
        for i in range(32):
            assert hash_hw[i] == hash[i], "hash incorrect"

        if VERBOSE >= 1:
            dut._log.info("------------------------------------------")
