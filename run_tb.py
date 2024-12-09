#!/usr/bin/env python3
#
# Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
# for details.
#
# Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
#
# Python script that:
# 1. generates test vectors for the Ascon core
# 2. runs verilog test benches
# 3. compares the test bench output to an Ascon software implementation

import argparse, io, random, subprocess
# from ascon_v12 import *
from ascon import *

# Terminal colors
OKGREEN = "\033[92m"
WARNING = "\033[93m"
FAIL = "\033[91m"
ENDC = "\033[0m"

# Specify verbose output of Ascon computations in software
VERBOSE_AEAD_SW = 0
VERBOSE_HASH_SW = 0

# Specify encryption, decryption, and/or hash operations for the Ascon core
INCL_ENC = 1
INCL_DEC = 1
INCL_HASH = 1

# Print inputs/outputs of Ascon software implementation
def print_result(result, ad, pt, ct, tag, msg, hash):
    print()
    if result:
        print(f"{FAIL}")
    print("ad   = " + "".join("{:02x}".format(x) for x in ad))
    print("pt   = " + "".join("{:02x}".format(x) for x in pt))
    print("ct   = " + "".join("{:02x}".format(x) for x in ct))
    print("tag  = " + "".join("{:02x}".format(x) for x in tag))
    print("msg  = " + "".join("{:02x}".format(x) for x in msg))
    print("hash = " + "".join("{:02x}".format(x) for x in hash))
    if result:
        print(f"ERROR{ENDC}")
        exit()
    else:
        print(f"{OKGREEN}PASS{ENDC}")


# Print inputs/outputs of Ascon software implementation
def check_result(name, val_sw, val_hw):
    if (val_sw != val_hw):
        print()
        print(f"{FAIL}")
        print(name)
        print("".join("{:02x}".format(x) for x in val_sw))
        print("".join("{:02x}".format(x) for x in val_hw))
        print(f"ERROR{ENDC}")
        exit()


# Write data segment to test vector file
def write_data_seg(f, x, xlen):
    for i in range(xlen):
        if (i % 4) == 0:
            f.write("DAT ")
        f.write("{:02X}".format(x[i]))
        if (i % 4) == 3:
            f.write("\n")
    f.write("\n")


# Write test vector file
def write_tv_file(key, npub, ad, msg, ct, tag, hash):
    f = open("rtl/tv.sv", "w")
    f.write("logic [127:0] tb_key = 128'h")
    for i in range(len(key)): f.write("{:02X}".format(key[-i-1]))
    f.write(";\n")
    f.write("logic [127:0] tb_nonce = 128'h")
    for i in range(len(npub)): f.write("{:02X}".format(npub[-i-1]))
    f.write(";\n")
    f.write("logic [127:0] tb_tag = 128'h")
    for i in range(len(tag)): f.write("{:02X}".format(tag[-i-1]))
    f.write(";\n")
    f.write("logic [{}:0] tb_ad = {}'h".format(len(ad)*8-1,len(ad)*8))
    for i in range(len(ad)): f.write("{:02X}".format(ad[-i-1]))
    f.write(";\n")
    f.write("logic [{}:0] tb_msg = {}'h".format(len(msg)*8-1,len(msg)*8))
    for i in range(len(msg)): f.write("{:02X}".format(msg[-i-1]))
    f.write(";\n")
    f.write("logic [{}:0] tb_ct = {}'h".format(len(ct)*8-1,len(ct)*8))
    for i in range(len(ct)): f.write("{:02X}".format(ct[-i-1]))
    f.write(";\n")
    f.write("logic [{}:0] tb_hash = {}'h".format(len(hash)*8-1,len(hash)*8))
    for i in range(len(hash)): f.write("{:02X}".format(hash[-i-1]))
    f.write(";\n")
    f.close()


def run_tb(key, npub, ad, msg, variant):
    """
    Pad inputs, generate a test vector file, and run verilog test bench
    """
    # Compute Ascon in software
    ct, tag = ascon_encrypt(key, npub, ad, msg)
    hash = ascon_hash(msg)

    # Write test vector file for verilog test bench to "tv/tv.txt"
    write_tv_file(key, npub, ad, msg, ct, tag, hash)

    # Run verilog test bench and parse the output
    ps = subprocess.run(
        ["make", variant],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        text=True,
    )
    stdout = io.StringIO(ps.stdout)
    hw_ct = bytearray()
    hw_tag = bytearray()
    hw_msg = bytearray()
    hw_hash = bytearray()
    hw_auth = bytearray()
    for line in stdout.readlines():
        if "msg  =>" in line:
            hw_msg  = bytearray.fromhex(line[8 : 8 + 16]) + hw_msg
        if "ct   =>" in line:
            hw_ct   = bytearray.fromhex(line[8 : 8 + 16]) + hw_ct
        if "tag  =>" in line:
            hw_tag  = bytearray.fromhex(line[8 : 8 + 16]) + hw_tag
        if "hash =>" in line:
            hw_hash = bytearray.fromhex(line[8 : 8 + 16]) + hw_hash
        if "auth =>" in line:
            hw_auth = bytearray.fromhex("0" + line[8 : 8 + 1])

    print("ad   = " + "".join("{:02x}".format(x) for x in ad[::-1]))
    print("msg  = " + "".join("{:02x}".format(x) for x in msg[::-1]))
    print("ct   = " + "".join("{:02x}".format(x) for x in ct[::-1]))
    print("tag  = " + "".join("{:02x}".format(x) for x in tag[::-1]))
    print("hash = " + "".join("{:02x}".format(x) for x in hash[::-1]))

    # Compare test bench output to software implementation
    result = 0
    if INCL_ENC:
        check_result("ct", ct[::-1], hw_ct)
        check_result("tag", tag[::-1], hw_tag)
    if INCL_DEC:
        check_result("msg", msg[::-1], hw_msg)
        if (hw_auth[0] != 1):
            print(f"{FAIL}")
            print("tag verification")
            print(f"ERROR{ENDC}")
            exit()
    if INCL_HASH:
        check_result("hash", hash[::-1], hw_hash)


# Generate one test vector and run test bench
def run_hw_single(variant):
    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    npub = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    ad = bytes.fromhex("00010203")
    pt = bytes.fromhex("00010203")
    print(variant)
    print("key  = " + "".join("{:02x}".format(x) for x in key[::-1]))
    print("npub = " + "".join("{:02x}".format(x) for x in npub[::-1]))
    run_tb(key, npub, ad, pt, variant)
    print(f"{OKGREEN}ALL PASS{ENDC}")


# Generate multiple test vectors and run test bench
def run_hw_sweep(variant):
    key_len = 16
    npub_len = 16
    max_ad_len = 16
    max_pt_len = 16
    random.seed(42)
    key = random.randbytes(key_len)
    npub = random.randbytes(npub_len)
    print(variant)
    print("key  = " + "".join("{:02x}".format(x) for x in key))
    print("npub = " + "".join("{:02x}".format(x) for x in npub))
    for ad_len in range(max_ad_len):
        for pt_len in range(max_pt_len):
            ad = random.randbytes(ad_len)
            pt = random.randbytes(pt_len)
            run_tb(key, npub, ad, pt, variant)
    print(f"{OKGREEN}ALL PASS{ENDC}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-s",
        "--single",
        action="store",
        nargs="*",
        help="Perform a single test bench run.",
    )
    parser.add_argument(
        "-w",
        "--sweep",
        action="store",
        nargs="*",
        help="Sweep over inputs of different lengths and perform test bench runs.",
    )
    parser.add_argument(
        "-v",
        "--variant",
        nargs="?",
        default=1,
        type=int,
        help="The variant of the Ascon core: 1, 2, or 3",
    )

    args = parser.parse_args()
    variant = f"v{args.variant}"

    if args.single is not None:
        run_hw_single(variant)
    else:
        run_hw_sweep(variant)
