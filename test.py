# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import test_helpers
from ascon import *
from test_helpers import (
    Data,
    Fsm,
    Mode,
    clear_bdi,
    corrupt,
    cycle_cnt,
    init_dut,
    log,
    receive_data,
    run_aead_dec,
    run_aead_enc,
    run_cxof,
    run_hash,
    run_xof,
    send_data,
    send_key,
    timeout,
    toggle,
)

RUNS = [0, 1, 2, 3, 4, 5, 6, 7, 8]


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
    mode = Mode.M_AEAD128_ENC
    if cocotb.__version__[0] == "2":
        clock = Clock(dut.clk, 1, unit="ns")
    else:
        clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    cocotb.start_soon(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    key = bytearray([random.randint(0, 255) for x in range(16)])
    npub = bytearray([random.randint(0, 255) for x in range(16)])

    log(dut, verbose=2, dashes=1, key=key, npub=npub)

    for msglen in RUNS:
        for adlen in RUNS:
            dut._log.info("test      %s ad:%d msg:%d", mode.name, adlen, msglen)

            ad = bytearray([random.randint(0, 255) for x in range(adlen)])
            pt = bytearray([random.randint(0, 255) for x in range(msglen)])

            # compute in software
            (ct, tag) = ascon_encrypt(key, npub, ad, pt)

            log(dut, verbose=2, dashes=0, ad=ad, pt=pt, ct=ct, tag=tag)

            cycle_task = cocotb.start_soon(cycle_cnt(dut))
            timeout_task = cocotb.start_soon(timeout(dut))
            try:
                cocotb.start_soon(toggle(dut, "dut.mode", mode.value))

                # send key
                await send_key(dut, key)

                # send nonce
                await send_data(
                    dut, npub, Data.D_NONCE.value, 0, (adlen == 0) and (msglen == 0)
                )

                # send ad
                if adlen > 0:
                    await send_data(dut, ad, Data.D_AD.value, 0, (msglen == 0))

                # send pt/ct
                if msglen > 0:
                    ct_hw = await send_data(dut, pt, Data.D_MSG.value, 1, 1)
                    log(dut, verbose=2, dashes=0, ct_hw=ct_hw)

                # receive tag
                tag_hw = await receive_data(dut, Data.D_TAG.value)
                log(dut, verbose=2, dashes=0, tag_hw=tag_hw)

                # check ciphertext
                for i in range(len(ct)):
                    assert ct_hw[i] == ct[i], "ct mismatch"

                # check tag
                for i in range(len(tag)):
                    assert tag_hw[i] == tag[i], "tag mismatch"

                await cycle_task.complete
            finally:
                timeout_task.cancel()
            log(dut, verbose=1, dashes=1)


@cocotb.test()
async def test_enc_backpressure(dut):
    stall_output = test_helpers.STALL_OUTPUT
    test_helpers.STALL_OUTPUT = 1
    try:
        await test_enc.func(dut)
    finally:
        test_helpers.STALL_OUTPUT = stall_output


@cocotb.test()
async def test_enc_rare_input(dut):
    stall_input = test_helpers.STALL_INPUT
    test_helpers.STALL_INPUT = 1
    try:
        await test_enc.func(dut)
    finally:
        test_helpers.STALL_INPUT = stall_input


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
    mode = Mode.M_AEAD128_DEC
    if cocotb.__version__[0] == "2":
        clock = Clock(dut.clk, 1, unit="ns")
    else:
        clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    cocotb.start_soon(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    key = bytearray([random.randint(0, 255) for x in range(16)])
    npub = bytearray([random.randint(0, 255) for x in range(16)])

    log(dut, verbose=2, dashes=1, key=key, npub=npub)

    for msglen in RUNS:
        for adlen in RUNS:
            dut._log.info("test      %s ad:%d msg:%d", mode.name, adlen, msglen)

            ad = bytearray([random.randint(0, 255) for x in range(adlen)])
            pt = bytearray([random.randint(0, 255) for x in range(msglen)])

            # compute in software
            (ct, tag) = ascon_encrypt(key, npub, ad, pt)

            await RisingEdge(dut.clk)

            log(dut, verbose=2, dashes=0, ad=ad, pt=pt, ct=ct, tag=tag)

            cycle_task = cocotb.start_soon(cycle_cnt(dut))
            timeout_task = cocotb.start_soon(timeout(dut))
            try:
                cocotb.start_soon(toggle(dut, "dut.mode", mode.value))

                # send key
                await send_key(dut, key)

                # send nonce
                await send_data(
                    dut, npub, Data.D_NONCE.value, 0, (adlen == 0) and (msglen == 0)
                )

                # send ad
                if adlen > 0:
                    await send_data(dut, ad, Data.D_AD.value, 0, (msglen == 0))

                # send pt/ct
                if msglen > 0:
                    pt_hw = await send_data(dut, ct, Data.D_MSG.value, 1, 1)
                    log(dut, verbose=2, dashes=0, pt_hw=pt_hw)

                # send tag
                await send_data(dut, tag, Data.D_TAG.value, 0, 1)

                # check plaintext
                for i in range(len(pt)):
                    assert pt_hw[i] == pt[i], "pt mismatch"

                # check tag verification
                await RisingEdge(dut.clk)
                assert int(dut.auth_valid.value) == 1, "auth_valid not asserted"
                assert int(dut.auth.value) == 1

                await cycle_task.complete
            finally:
                timeout_task.cancel()
            log(dut, verbose=1, dashes=1)


@cocotb.test()
async def test_dec_backpressure(dut):
    stall_output = test_helpers.STALL_OUTPUT
    test_helpers.STALL_OUTPUT = 1
    try:
        await test_dec.func(dut)
    finally:
        test_helpers.STALL_OUTPUT = stall_output


@cocotb.test()
async def test_dec_rare_input(dut):
    stall_input = test_helpers.STALL_INPUT
    test_helpers.STALL_INPUT = 1
    try:
        await test_dec.func(dut)
    finally:
        test_helpers.STALL_INPUT = stall_input


# ,------.                                       ,--.      ,------.       ,--.,--.
# |  .-.  \  ,---.  ,---.,--.--.,--. ,--.,---. ,-'  '-.    |  .---',--,--.`--'|  |
# |  |  \  :| .-. :| .--'|  .--' \  '  /| .-. |'-.  .-'    |  `--,' ,-.  |,--.|  |
# |  '--'  /\   --.\ `--.|  |     \   ' | '-' '  |  |      |  |`  \ '-'  ||  ||  |
# `-------'  `----' `---'`--'   .-'  /  |  |-'   `--'      `--'    `--`--'`--'`--'
#                               `---'   `--'


@cocotb.test()
async def test_dec_fail(dut):

    # init test
    random.seed(31416)
    mode = Mode.M_AEAD128_DEC
    if cocotb.__version__[0] == "2":
        clock = Clock(dut.clk, 1, unit="ns")
    else:
        clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    cocotb.start_soon(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    key = bytearray([random.randint(0, 255) for x in range(16)])
    npub = bytearray([random.randint(0, 255) for x in range(16)])

    log(dut, verbose=2, dashes=1, key=key, npub=npub)

    for msglen in RUNS:
        for adlen in RUNS:
            dut._log.info("test      %s ad:%d msg:%d", mode.name, adlen, msglen)

            # flip coin if data is corrupted
            corrupt_key = random.randint(0, 4) % 5 == 0
            corrupt_nonce = random.randint(0, 4) % 5 == 0
            corrupt_ad = random.randint(0, 4) % 5 == 0 and adlen > 0
            corrupt_ct = random.randint(0, 4) % 5 == 0 and msglen > 0
            corrupt_tag = random.randint(0, 4) % 5 == 0
            dec_fail = corrupt_key or corrupt_nonce or corrupt_ad or corrupt_ct
            auth_fail = dec_fail or corrupt_tag

            ad = bytearray([random.randint(0, 255) for x in range(adlen)])
            pt = bytearray([random.randint(0, 255) for x in range(msglen)])

            # compute in software
            (ct, tag) = ascon_encrypt(key, npub, ad, pt)

            await RisingEdge(dut.clk)

            log(dut, verbose=2, dashes=0, ad=ad, pt=pt, ct=ct, tag=tag)

            cycle_task = cocotb.start_soon(cycle_cnt(dut))
            timeout_task = cocotb.start_soon(timeout(dut))
            try:
                cocotb.start_soon(toggle(dut, "dut.mode", mode.value))

                # send key
                if corrupt_key:
                    await send_key(dut, corrupt(key))
                else:
                    await send_key(dut, key)

                # send nonce
                if corrupt_nonce:
                    await send_data(
                        dut,
                        corrupt(npub),
                        Data.D_NONCE.value,
                        0,
                        (adlen == 0) and (msglen == 0),
                    )
                else:
                    await send_data(
                        dut, npub, Data.D_NONCE.value, 0, (adlen == 0) and (msglen == 0)
                    )

                # send ad
                if adlen > 0:
                    if corrupt_ad:
                        await send_data(
                            dut, corrupt(ad), Data.D_AD.value, 0, (msglen == 0)
                        )
                    else:
                        await send_data(dut, ad, Data.D_AD.value, 0, (msglen == 0))

                # send pt/ct
                if msglen > 0:
                    if corrupt_ct:
                        pt_hw = await send_data(
                            dut, corrupt(ct), Data.D_MSG.value, 1, 1
                        )
                    else:
                        pt_hw = await send_data(dut, ct, Data.D_MSG.value, 1, 1)
                    log(dut, verbose=2, dashes=0, pt_hw=pt_hw)

                # send corrupt tag
                if corrupt_tag:
                    await send_data(dut, corrupt(tag), Data.D_TAG.value, 0, 1)
                else:
                    await send_data(dut, tag, Data.D_TAG.value, 0, 1)

                # Unmodified decryption inputs must reproduce the plaintext.
                if not dec_fail and msglen > 0:
                    assert pt_hw == list(pt), "error: plaintext mismatch"

                # Authentication determines whether any modified input is rejected.
                await RisingEdge(dut.clk)
                assert int(dut.auth_valid.value) == 1, (
                    "error: authentication result not valid"
                )
                assert int(dut.auth.value) == (not auth_fail), (
                    "error: unexpected authentication result"
                )

                await cycle_task.complete
            finally:
                timeout_task.cancel()
            log(dut, verbose=1, dashes=1)


# ,--.  ,--.               ,--.
# |  '--'  | ,--,--. ,---. |  ,---.
# |  .--.  |' ,-.  |(  .-' |  .-.  |
# |  |  |  |\ '-'  |.-'  `)|  | |  |
# `--'  `--' `--`--'`----' `--' `--'


@cocotb.test()
async def test_hash(dut):

    # init test
    random.seed(31415)
    mode = Mode.M_HASH256
    if cocotb.__version__[0] == "2":
        clock = Clock(dut.clk, 1, unit="ns")
    else:
        clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    cocotb.start_soon(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    log(dut, verbose=1, dashes=1)

    for msglen in RUNS:
        dut._log.info("test      %s msg:%d", mode.name, msglen)

        msg = bytearray([random.randint(0, 255) for x in range(msglen)])

        # compute in software
        hash = ascon_hash(msg)

        log(dut, verbose=2, dashes=0, msg=msg, hash=hash)

        cycle_task = cocotb.start_soon(cycle_cnt(dut))
        timeout_task = cocotb.start_soon(timeout(dut))
        try:
            cocotb.start_soon(toggle(dut, "dut.mode", mode.value))

            if msglen == 0:
                cocotb.start_soon(toggle(dut, "dut.bdi_eot", 1))
                cocotb.start_soon(toggle(dut, "dut.bdi_eoi", 1))

            await RisingEdge(dut.clk)

            # send msg
            if msglen > 0:
                await send_data(dut, msg, Data.D_MSG.value, 0, 1)

            # receive hash
            hash_hw = await receive_data(dut, Data.D_HASH.value, 32)
            log(dut, verbose=2, dashes=0, hash_hw=hash_hw)

            # check hash
            for i in range(32):
                assert hash_hw[i] == hash[i], "hash incorrect"

            await cycle_task.complete
        finally:
            timeout_task.cancel()
        log(dut, verbose=1, dashes=1)


# ,--.   ,--.,-----. ,------.
#  \  `.'  /'  .-.  '|  .---'
#   .'    \ |  | |  ||  `--,
#  /  .'.  \'  '-'  '|  |`
# '--'   '--'`-----' `--'


@cocotb.test()
async def test_xof(dut):

    # init test
    random.seed(31415)
    mode = Mode.M_XOF128
    if cocotb.__version__[0] == "2":
        clock = Clock(dut.clk, 1, unit="ns")
    else:
        clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    cocotb.start_soon(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    log(dut, verbose=1, dashes=1)

    for msglen in RUNS:
        for xlen in RUNS:
            if xlen == 0:
                continue
            xoflen = xlen
            dut._log.info("test      %s msg:%d xof:%d", mode.name, msglen, xoflen)

            msg = bytearray([random.randint(0, 255) for x in range(msglen)])

            # compute in software
            xof = ascon_hash(msg, variant="Ascon-XOF128", hashlength=xoflen)

            log(dut, verbose=2, dashes=0, msg=msg, xof=xof)

            cycle_task = cocotb.start_soon(cycle_cnt(dut))
            timeout_task = cocotb.start_soon(timeout(dut))
            try:
                cocotb.start_soon(toggle(dut, "dut.mode", mode.value))

                if msglen == 0:
                    cocotb.start_soon(toggle(dut, "dut.bdi_eot", 1))
                    cocotb.start_soon(toggle(dut, "dut.bdi_eoi", 1))

                await RisingEdge(dut.clk)

                # send msg
                if msglen > 0:
                    await send_data(dut, msg, Data.D_MSG.value, 0, 1)

                # receive xof
                xof_hw = await receive_data(dut, Data.D_HASH.value, xoflen, bdo_eoo=1)
                log(dut, verbose=2, dashes=0, xof_hw=xof_hw)

                await RisingEdge(dut.clk)

                # check hash
                for i in range(xoflen):
                    assert hex(xof_hw[i]) == hex(xof[i]), "xof incorrect"

                await cycle_task.complete
            finally:
                timeout_task.cancel()
            log(dut, verbose=1, dashes=1)


#  ,-----.,--.   ,--.,-----. ,------.
# '  .--./ \  `.'  /'  .-.  '|  .---'
# |  |      .'    \ |  | |  ||  `--,
# '  '--'\ /  .'.  \'  '-'  '|  |`
#  `-----''--'   '--'`-----' `--'


@cocotb.test()
async def test_cxof(dut):

    # init test
    random.seed(31415)
    mode = Mode.M_CXOF128
    if cocotb.__version__[0] == "2":
        clock = Clock(dut.clk, 1, unit="ns")
    else:
        clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start(start_high=False))
    cocotb.start_soon(toggle(dut, "dut.rst", 1))
    await RisingEdge(dut.clk)

    log(dut, verbose=1, dashes=1)

    for msglen in RUNS:
        for cstmlen in [0, 1, 2, 3, 4, 5, 6, 7, 8, 256]:
            for xlen in RUNS:
                if xlen == 0:
                    continue
                cxoflen = xlen
                cstm = bytearray([random.randint(0, 255) for x in range(cstmlen)])
                msg = bytearray([random.randint(0, 255) for x in range(msglen)])

                dut._log.info(
                    "test      %s cstm:%d msg:%d xof:%d",
                    mode.name,
                    cstmlen,
                    msglen,
                    cxoflen,
                )

                # compute in software
                cxof = ascon_hash(
                    msg, variant="Ascon-CXOF128", hashlength=cxoflen, customization=cstm
                )

                # prepend bit-length identifier block to cstm
                for i in range(8):
                    cstm.insert(0, 0)
                cstm[0] = (cstmlen * 8) % 256
                cstm[1] = min(((cstmlen * 8) >> 8), 8)

                log(dut, verbose=2, dashes=0, cstm=cstm, msg=msg, cxof=cxof)

                cycle_task = cocotb.start_soon(cycle_cnt(dut))
                timeout_task = cocotb.start_soon(timeout(dut))
                try:
                    cocotb.start_soon(toggle(dut, "dut.mode", mode.value))

                    await RisingEdge(dut.clk)

                    # send customization string
                    await send_data(dut, cstm, Data.D_AD.value, 0, (msglen == 0))

                    # send msg
                    if msglen > 0:
                        await send_data(dut, msg, Data.D_MSG.value, 0, 1)

                    # receive xof
                    cxof_hw = await receive_data(dut, Data.D_HASH.value, cxoflen, 1)
                    log(dut, verbose=2, dashes=0, cxof_hw=cxof_hw)

                    await RisingEdge(dut.clk)

                    # check cxof
                    for i in range(cxoflen):
                        assert hex(cxof_hw[i]) == hex(cxof[i]), "cxof incorrect"

                    await cycle_task.complete
                finally:
                    timeout_task.cancel()
                log(dut, verbose=1, dashes=1)


#   ,---.  ,--.    ,--------.              ,--.
#  /  O  \ |  |    '--.  .--',---.  ,---.,-'  '-. ,---.
# |  .-.  ||  |       |  |  | .-. :(  .-''-.  .-'(  .-'
# |  | |  ||  |       |  |  \   --..-'  `) |  |  .-'  `)
# `--' `--'`--'       `--'   `----'`----'  `--'  `----'


# 1. Key reuse (key_valid == 0 when mode is sampled)
@cocotb.test()
async def test_key_reuse(dut):
    random.seed(202601)
    await init_dut(dut)

    key = bytes(random.randint(0, 255) for _ in range(16))
    cases = [(0, 0), (0, 1), (1, 0), (7, 9), (16, 16), (17, 33)]

    # First operation loads the key; subsequent enc & dec operations reuse it.
    first = True
    for adlen, msglen in cases:
        npub = bytes(random.randint(0, 255) for _ in range(16))
        ad = bytes(random.randint(0, 255) for _ in range(adlen))
        pt = bytes(random.randint(0, 255) for _ in range(msglen))
        ct_ref, tag_ref = ascon_encrypt(key, npub, ad, pt)

        ct_hw, tag_hw = await run_aead_enc(dut, key, npub, ad, pt, send_key_flag=first)
        assert ct_hw == ct_ref, "key reuse enc ct mismatch"
        assert tag_hw == tag_ref, "key reuse enc tag mismatch"
        first = False

        pt_hw, auth_valid, auth = await run_aead_dec(
            dut, key, npub, ad, ct_ref, tag_ref, send_key_flag=False
        )
        assert pt_hw == pt, "key reuse dec pt mismatch"
        assert auth_valid == 1 and auth == 1, "key reuse dec auth failed"

    # Load a second key and confirm the key register updates cleanly.
    key2 = bytes(random.randint(0, 255) for _ in range(16))
    npub2 = bytes(random.randint(0, 255) for _ in range(16))
    ad2 = bytes(random.randint(0, 255) for _ in range(11))
    pt2 = bytes(random.randint(0, 255) for _ in range(19))
    ct_ref2, tag_ref2 = ascon_encrypt(key2, npub2, ad2, pt2)
    ct_hw2, tag_hw2 = await run_aead_enc(dut, key2, npub2, ad2, pt2, send_key_flag=True)
    assert ct_hw2 == ct_ref2 and tag_hw2 == tag_ref2, "reloaded key enc mismatch"
    pt_hw2, auth_valid2, auth2 = await run_aead_dec(
        dut, key2, npub2, ad2, ct_ref2, tag_ref2, send_key_flag=False
    )
    assert pt_hw2 == pt2 and auth_valid2 == 1 and auth2 == 1


# 2. Back-to-back cross-mode sequences without reset
@cocotb.test()
async def test_cross_mode_sequences(dut):
    random.seed(202602)
    await init_dut(dut)

    key = bytes(random.randint(0, 255) for _ in range(16))
    npub = bytes(random.randint(0, 255) for _ in range(16))
    ad = bytes(random.randint(0, 255) for _ in range(13))
    pt = bytes(random.randint(0, 255) for _ in range(21))
    ct_ref, tag_ref = ascon_encrypt(key, npub, ad, pt)

    # XOF with non-block-aligned output (5, 13, 33 bytes) -> Hash256
    for xoflen in [5, 13, 33]:
        msg_x = bytes(random.randint(0, 255) for _ in range(11))
        xof_ref = ascon_hash(msg_x, variant="Ascon-XOF128", hashlength=xoflen)
        assert await run_xof(dut, msg_x, xoflen) == xof_ref

        msg_h = bytes(random.randint(0, 255) for _ in range(17))
        hash_ref = ascon_hash(msg_h, variant="Ascon-Hash256", hashlength=32)
        assert await run_hash(dut, msg_h) == hash_ref

    # Hash256 -> CXOF128 (non-block-aligned) -> Hash256
    msg_h2 = bytes(random.randint(0, 255) for _ in range(8))
    assert await run_hash(dut, msg_h2) == ascon_hash(msg_h2)

    cstm = bytes(random.randint(0, 255) for _ in range(15))
    msg_c = bytes(random.randint(0, 255) for _ in range(9))
    assert await run_cxof(dut, msg_c, cstm, 19) == ascon_hash(
        msg_c, variant="Ascon-CXOF128", hashlength=19, customization=cstm
    )

    msg_h3 = b""
    assert await run_hash(dut, msg_h3) == ascon_hash(msg_h3)

    # AEAD DEC (auth=1) -> AEAD ENC (verify auth_valid & auth clear)
    pt_hw, auth_valid, auth = await run_aead_dec(dut, key, npub, ad, ct_ref, tag_ref)
    assert pt_hw == pt and auth_valid == 1 and auth == 1

    ct_hw, tag_hw = await run_aead_enc(dut, key, npub, ad, pt, send_key_flag=False)
    assert ct_hw == ct_ref and tag_hw == tag_ref
    assert int(dut.auth_valid.value) == 0 and int(dut.auth.value) == 0

    # AEAD DEC fail (auth=0, auth_valid=1) -> XOF -> AEAD DEC pass (reusing key!)
    _, auth_valid, auth = await run_aead_dec(
        dut, key, npub, ad, ct_ref, corrupt(tag_ref), send_key_flag=False
    )
    assert auth_valid == 1 and auth == 0

    msg_x2 = bytes(random.randint(0, 255) for _ in range(25))
    assert await run_xof(dut, msg_x2, 40) == ascon_hash(
        msg_x2, variant="Ascon-XOF128", hashlength=40
    )

    pt_hw, auth_valid, auth = await run_aead_dec(
        dut, key, npub, ad, ct_ref, tag_ref, send_key_flag=False
    )
    assert pt_hw == pt and auth_valid == 1 and auth == 1


# 3. Combined stalls & stalls across hash / xof / cxof / dec_fail + key_valid stalls
@cocotb.test()
async def test_all_modes_combined_stalls(dut):
    old_in, old_out = test_helpers.STALL_INPUT, test_helpers.STALL_OUTPUT
    test_helpers.STALL_INPUT = 1
    test_helpers.STALL_OUTPUT = 1
    try:
        random.seed(202603)
        await init_dut(dut)

        key = bytes(random.randint(0, 255) for _ in range(16))
        npub = bytes(random.randint(0, 255) for _ in range(16))

        # AEAD enc / dec / dec_fail with simultaneous input + output + key_valid stalls
        for adlen, msglen in [(0, 0), (0, 5), (5, 0), (7, 9), (16, 17)]:
            ad = bytes(random.randint(0, 255) for _ in range(adlen))
            pt = bytes(random.randint(0, 255) for _ in range(msglen))
            ct_ref, tag_ref = ascon_encrypt(key, npub, ad, pt)

            ct_hw, tag_hw = await run_aead_enc(dut, key, npub, ad, pt)
            assert ct_hw == ct_ref and tag_hw == tag_ref

            pt_hw, auth_valid, auth = await run_aead_dec(
                dut, key, npub, ad, ct_ref, tag_ref
            )
            assert pt_hw == pt and auth_valid == 1 and auth == 1

            _, auth_valid, auth = await run_aead_dec(
                dut, key, npub, ad, ct_ref, corrupt(tag_ref)
            )
            assert auth_valid == 1 and auth == 0

        # Hash256 with combined stalls
        for msglen in [0, 1, 7, 8, 9, 17]:
            msg = bytes(random.randint(0, 255) for _ in range(msglen))
            assert await run_hash(dut, msg) == ascon_hash(msg)

        # XOF128 with combined stalls
        for msglen, xoflen in [(0, 1), (1, 7), (8, 16), (9, 33)]:
            msg = bytes(random.randint(0, 255) for _ in range(msglen))
            assert await run_xof(dut, msg, xoflen) == ascon_hash(
                msg, variant="Ascon-XOF128", hashlength=xoflen
            )

        # CXOF128 with combined stalls
        for cstmlen, msglen, cxoflen in [(0, 0, 5), (3, 7, 16), (8, 9, 33)]:
            cstm = bytes(random.randint(0, 255) for _ in range(cstmlen))
            msg = bytes(random.randint(0, 255) for _ in range(msglen))
            assert await run_cxof(dut, msg, cstm, cxoflen) == ascon_hash(
                msg, variant="Ascon-CXOF128", hashlength=cxoflen, customization=cstm
            )
    finally:
        test_helpers.STALL_INPUT = old_in
        test_helpers.STALL_OUTPUT = old_out


# 4. Garbage bytes on invalid BDI byte lanes (padding & output lane masking)
@cocotb.test()
async def test_invalid_bdi_lane_garbage(dut):
    old_garbage = test_helpers.GARBAGE_INVALID_LANES
    test_helpers.GARBAGE_INVALID_LANES = 1
    try:
        random.seed(202604)
        await init_dut(dut)

        key = bytes(random.randint(0, 255) for _ in range(16))
        npub = bytes(random.randint(0, 255) for _ in range(16))

        for adlen in [1, 2, 3, 5, 7, 9, 15, 17]:
            for msglen in [1, 2, 3, 5, 7, 9, 15, 17]:
                ad = bytes(random.randint(0, 255) for _ in range(adlen))
                pt = bytes(random.randint(0, 255) for _ in range(msglen))
                ct_ref, tag_ref = ascon_encrypt(key, npub, ad, pt)

                ct_hw, tag_hw = await run_aead_enc(dut, key, npub, ad, pt)
                assert ct_hw == ct_ref and tag_hw == tag_ref

                pt_hw, auth_valid, auth = await run_aead_dec(
                    dut, key, npub, ad, ct_ref, tag_ref, send_key_flag=False
                )
                assert pt_hw == pt and auth_valid == 1 and auth == 1

        for msglen in [1, 2, 3, 5, 7, 9, 15]:
            msg = bytes(random.randint(0, 255) for _ in range(msglen))
            assert await run_hash(dut, msg) == ascon_hash(msg)
            cstm = bytes(random.randint(0, 255) for _ in range(msglen))
            assert await run_cxof(dut, msg, cstm, 17) == ascon_hash(
                msg, variant="Ascon-CXOF128", hashlength=17, customization=cstm
            )
    finally:
        test_helpers.GARBAGE_INVALID_LANES = old_garbage


# 5. Mid-operation async reset across major FSM states
@cocotb.test()
async def test_mid_operation_reset(dut):
    random.seed(202605)
    await init_dut(dut)

    has_fsm = hasattr(dut, "fsm_q")
    if not has_fsm:
        dut._log.info("skipping FSM-targeted mid-op reset (fsm_q not exposed)")
        return

    key = bytes(random.randint(0, 255) for _ in range(16))
    npub = bytes(random.randint(0, 255) for _ in range(16))
    ad = bytes(random.randint(0, 255) for _ in range(20))
    pt = bytes(random.randint(0, 255) for _ in range(20))
    ct_ref, tag_ref = ascon_encrypt(key, npub, ad, pt)

    async def abort_on_state(target_fsm, op_coro):
        op_task = cocotb.start_soon(op_coro)
        reached = False
        for _ in range(200):
            await RisingEdge(dut.clk)
            if int(dut.fsm_q.value) == target_fsm.value:
                reached = True
                break
        assert reached, f"did not reach state {target_fsm.name}"
        op_task.cancel()
        dut.mode.value = 0
        dut.key.value = 0
        dut.key_valid.value = 0
        dut.bdo_eoo.value = 0
        await clear_bdi(dut)
        dut.rst.value = 1
        await RisingEdge(dut.clk)
        dut.rst.value = 0
        await RisingEdge(dut.clk)
        assert int(dut.fsm_q.value) == Fsm.IDLE.value, (
            f"FSM did not return to IDLE after reset in {target_fsm.name}"
        )
        assert int(dut.auth_valid.value) == 0 and int(dut.auth.value) == 0

    for target in [
        Fsm.LD_KEY,
        Fsm.INIT,
        Fsm.ABS_AD,
        Fsm.PRO_AD,
        Fsm.ABS_MSG,
        Fsm.FINAL,
    ]:
        await abort_on_state(target, run_aead_enc(dut, key, npub, ad, pt))
        ct_hw, tag_hw = await run_aead_enc(dut, key, npub, ad, pt)
        assert ct_hw == ct_ref and tag_hw == tag_ref, (
            f"post-reset AEAD enc failed after abort in {target.name}"
        )

    await abort_on_state(Fsm.VER_TAG, run_aead_dec(dut, key, npub, ad, ct_ref, tag_ref))
    pt_hw, auth_valid, auth = await run_aead_dec(dut, key, npub, ad, ct_ref, tag_ref)
    assert pt_hw == pt and auth_valid == 1 and auth == 1

    await abort_on_state(Fsm.SQZ_HASH, run_hash(dut, pt))
    assert await run_hash(dut, pt) == ascon_hash(pt)


# 6. Protocol & boundary edge cases
@cocotb.test()
async def test_protocol_and_boundary_edge_cases(dut):
    random.seed(202606)
    await init_dut(dut)

    # 6a. Asserting bdo_eoo=1 during M_HASH256 must still output all 32 bytes.
    for msglen in [0, 5, 16]:
        msg = bytes(random.randint(0, 255) for _ in range(msglen))
        assert await run_hash(dut, msg, bdo_eoo=1) == ascon_hash(msg), (
            "M_HASH256 truncated when bdo_eoo=1"
        )

    # 6b. Driving M_INVALID and out-of-range mode values (6..15) in IDLE must not lock up.
    for bad_mode in [0, 6, 7, 8, 12, 15]:
        dut.mode.value = bad_mode
        await RisingEdge(dut.clk)
        dut.mode.value = 0
        await RisingEdge(dut.clk)
        if hasattr(dut, "fsm_q"):
            assert int(dut.fsm_q.value) == Fsm.IDLE.value, (
                f"invalid mode {bad_mode} left IDLE"
            )
    assert await run_hash(dut, b"alive") == ascon_hash(b"alive")

    # 6c. Regression test for KADD_2: driving non-D_AD/non-D_MSG bdi_type with bdi_valid!=0
    # while waiting in KADD_2 must stall in KADD_2 instead of looping/corrupting state.
    key = bytes(random.randint(0, 255) for _ in range(16))
    npub = bytes(random.randint(0, 255) for _ in range(16))
    ad = bytes(random.randint(0, 255) for _ in range(10))
    pt = bytes(random.randint(0, 255) for _ in range(10))
    ct_ref, tag_ref = ascon_encrypt(key, npub, ad, pt)

    cycle_task = cocotb.start_soon(cycle_cnt(dut))
    timeout_task = cocotb.start_soon(timeout(dut))
    try:
        cocotb.start_soon(toggle(dut, "dut.mode", Mode.M_AEAD128_ENC.value))
        await send_key(dut, key)
        await send_data(dut, npub, Data.D_NONCE.value, 0, 0)
        # Drive bogus bdi_type (D_TAG) with bdi_valid != 0 across INIT -> KADD_2
        for _ in range(25):
            dut.bdi.value = 0xDEADBEEF
            dut.bdi_valid.value = 1
            dut.bdi_type.value = Data.D_TAG.value
            dut.bdi_eot.value = 0
            dut.bdi_eoi.value = 0
            await RisingEdge(dut.clk)
        await clear_bdi(dut)
        await send_data(dut, ad, Data.D_AD.value, 0, 0)
        ct_hw = bytes(await send_data(dut, pt, Data.D_MSG.value, 1, 1))
        tag_hw = bytes(await receive_data(dut, Data.D_TAG.value))
        await cycle_task.complete
    finally:
        timeout_task.cancel()
    assert ct_hw == ct_ref and tag_hw == tag_ref, (
        "KADD_2 bogus bdi_type corrupted state"
    )

    # 6d. Longer XOF outputs (64 and 128 bytes)
    for xoflen in [64, 128]:
        msg = bytes(random.randint(0, 255) for _ in range(19))
        assert await run_xof(dut, msg, xoflen) == ascon_hash(
            msg, variant="Ascon-XOF128", hashlength=xoflen
        )

    # 6e. CXOF customization lengths around 64-bit boundaries (15, 16, 17, 255, 256)
    for cstmlen in [15, 16, 17, 255, 256]:
        cstm = bytes(random.randint(0, 255) for _ in range(cstmlen))
        msg = bytes(random.randint(0, 255) for _ in range(9))
        assert await run_cxof(dut, msg, cstm, 32) == ascon_hash(
            msg, variant="Ascon-CXOF128", hashlength=32, customization=cstm
        )


# 7. Official NIST SP 800-232 Known Answer Tests (KATs) from ascon/ascon-c
@cocotb.test()
async def test_nist_sp800_232_kats(dut):
    await init_dut(dut)

    # Ascon-AEAD128 (LWC_AEAD_KAT_128_128.txt: Counts 1, 2, 11, 49, 143, 739)
    aead_kats = [
        (
            "000102030405060708090A0B0C0D0E0F",
            "101112131415161718191A1B1C1D1E1F",
            "",
            "",
            "4F9C278211BEC9316BF68F46EE8B2EC6",
        ),
        (
            "000102030405060708090A0B0C0D0E0F",
            "101112131415161718191A1B1C1D1E1F",
            "",
            "30",
            "CCCB674FE18A09A285D6AB11B35675C0",
        ),
        (
            "000102030405060708090A0B0C0D0E0F",
            "101112131415161718191A1B1C1D1E1F",
            "",
            "30313233343536373839",
            "35BB5B5EBB8F21B1694603345397A443",
        ),
        (
            "000102030405060708090A0B0C0D0E0F",
            "101112131415161718191A1B1C1D1E1F",
            "20",
            "303132333435363738393A3B3C3D3E",
            "2089CB1DE2AE7D3E45BA7E9CC293548546",
        ),
        (
            "000102030405060708090A0B0C0D0E0F",
            "101112131415161718191A1B1C1D1E1F",
            "20212223",
            "30313233343536373839",
            "120429961A1BDA5D8D62C4FB0B1B262C1A679ED5",
        ),
        (
            "000102030405060708090A0B0C0D0E0F",
            "101112131415161718191A1B1C1D1E1F",
            "202122232425262728292A2B2C2D2E2F303132333435",
            "303132333435363738393A3B",
            "B83A1C62AD05C670D6E9220E0DD9BE46E43D8D6C06DA87F35628EEC3A75A60FAF8462C30962D",
        ),
    ]
    for k_hex, n_hex, pt_hex, ad_hex, ct_tag_hex in aead_kats:
        key = bytes.fromhex(k_hex)
        npub = bytes.fromhex(n_hex)
        pt = bytes.fromhex(pt_hex)
        ad = bytes.fromhex(ad_hex)
        exp_ct_tag = bytes.fromhex(ct_tag_hex)
        exp_ct, exp_tag = exp_ct_tag[:-16], exp_ct_tag[-16:]

        ct_hw, tag_hw = await run_aead_enc(dut, key, npub, ad, pt)
        assert ct_hw == exp_ct and tag_hw == exp_tag, "NIST AEAD128 enc KAT mismatch"

        pt_hw, auth_valid, auth = await run_aead_dec(
            dut, key, npub, ad, exp_ct, exp_tag
        )
        assert pt_hw == pt and auth_valid == 1 and auth == 1, (
            "NIST AEAD128 dec KAT mismatch"
        )

    # Ascon-Hash256 (LWC_HASH_KAT_128_256.txt: Counts 1, 2, 9, 10)
    hash_kats = [
        ("", "0B3BE5850F2F6B98CAF29F8FDEA89B64A1FA70AA249B8F839BD53BAA304D92B2"),
        ("00", "0728621035AF3ED2BCA03BF6FDE900F9456F5330E4B5EE23E7F6A1E70291BC80"),
        (
            "0001020304050607",
            "B88E497AE8E6FB641B87EF622EB8F2FCA0ED95383F7FFEBE167ACF1099BA764F",
        ),
        (
            "000102030405060708",
            "94269C30E0296E1EC86655041841823EFA1927F520FD58C8E9BCE6197878C1A6",
        ),
    ]
    for msg_hex, md_hex in hash_kats:
        assert await run_hash(dut, bytes.fromhex(msg_hex)) == bytes.fromhex(md_hex), (
            "NIST Hash256 KAT mismatch"
        )

    # Ascon-XOF128 (LWC_XOF_KAT_128_512.txt: Counts 1, 2, 9, 10)
    xof_kats = [
        (
            "",
            "473D5E6164F58B39DFD84AACDB8AE42EC2D91FED33388EE0D960D9B3993295C6"
            "AD77855A5D3B13FE6AD9E6098988373AF7D0956D05A8F1665D2C67D1A3AD10FF",
        ),
        (
            "00",
            "51430E0438ECDF642B393630D977625F5F337656BA58AB1E960784AC32A16E0D"
            "446405551F5469384F8EA283CF12E64FA72C426BFEBAEA3AA1529E2C4AB23A2F",
        ),
        (
            "0001020304050607",
            "8D1886F5D3EC4AF8D15B44BC62B74DA6EA91BC28FB82F9C34079B5ED6E38B6C9"
            "51803D7DFB3C5E512A0EF5E4060062A6FD067F9C73EF9BEE527411BDA67FC896",
        ),
        (
            "000102030405060708",
            "DB3013BFBBD132DC1D3152FD955ED48F7CBB675E9AD2A2FECF92B74C957592E0"
            "C89959E81C16FD07EAD9EEB8E40359C497AA20258B43D87EC69AD0BB0993FD38",
        ),
    ]
    for msg_hex, md_hex in xof_kats:
        assert await run_xof(dut, bytes.fromhex(msg_hex), 64) == bytes.fromhex(
            md_hex
        ), "NIST XOF128 KAT mismatch"

    # Ascon-CXOF128 (LWC_CXOF_KAT_128_512.txt: Counts 1, 2, 40, 191, 744)
    cxof_kats = [
        (
            "",
            "",
            "4F50159EF70BB3DAD8807E034EAEBD44C4FA2CBBC8CF1F05511AB66CDCC52990"
            "5CA12083FC186AD899B270B1473DC5F7EC88D1052082DCDFE69FB75D269E7B74",
        ),
        (
            "",
            "10",
            "0C93A483E7D574D49FE52CCE03EE646117977D57A8AA57704AB4DAF44B501430"
            "FF6AC11A5D1FD6F2154B5C65728268270C8BB578508487B8965718ADA6272FD6",
        ),
        (
            "00",
            "101112131415",
            "3EF91811D2A81F3E858C0D432BF1336B1978F942ED04615E967D6A3EBC6FA068"
            "2FEF76751F6E937330738D1922BFB4C5B22B5CB95467F97AA924B46C09FB7629",
        ),
        (
            "0001020304",
            "101112131415161718191A1B1C1D1E1F202122232425262728",
            "7A7CE2D60398691E1F532E4D552DCA691B8A1AF0800AB89C4788DED361A85375"
            "AE183B0F40117EF2ED0A9CA83D8E58F22EA45BA1858F8E4B70F6B26B5F9FD78F",
        ),
        (
            "000102030405060708090A0B0C0D0E0F101112131415",
            "101112131415161718191A1B1C1D1E1F20",
            "4C900AD6AFA7EC5DCA82DCD344C43D9403A4879CCC2DC9CAAF0FDCC79F39F65E"
            "5331C8AC43AE6E76BE0C7E5539298FDA17A3F693686C01449923947EE3A3E83A",
        ),
    ]
    for msg_hex, z_hex, md_hex in cxof_kats:
        assert await run_cxof(
            dut, bytes.fromhex(msg_hex), bytes.fromhex(z_hex), 64
        ) == bytes.fromhex(md_hex), "NIST CXOF128 KAT mismatch"
