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
INCL_ENC = 0
INCL_DEC = 0
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
    print()
    if (val_sw != val_hw):
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
def write_tv_file(key, npub, ad, pt, ct, tag, msg):
    f = open("tv/tv.txt", "w")

    if INCL_ENC:
        f.write("# Load key\n")
        f.write("INS 30{:06x}\n".format(len(key)))
        write_data_seg(f, key, len(key))

        f.write("# Specify authenticated encryption\n")
        f.write("INS 00000000\n")
        f.write("\n")

        f.write("# Load nonce\n")
        if ((len(ad)==0) and (len(pt)==0)): f.write("INS 41{:06x}\n".format(len(npub)))
        else: f.write("INS 40{:06x}\n".format(len(npub)))
        write_data_seg(f, npub, len(npub))

        if len(ad) > 0:
            f.write("# Load associated data\n")
            if (len(pt)==0): f.write("INS 51{:06x}\n".format(len(ad)))
            else: f.write("INS 50{:06x}\n".format(len(ad)))
            write_data_seg(f, ad, len(ad))

        if (len(pt)>0):
            f.write("# Load plaintext\n")
            f.write("INS 61{:06X}\n".format(len(pt)))
            write_data_seg(f, pt, len(pt))

    if INCL_DEC:
        if not INCL_ENC:
            f.write("# Load key\n")
            f.write("INS 30{:06x}\n".format(len(key)))
            write_data_seg(f, key, len(key))

        f.write("# Specify authenticated decryption\n")
        f.write("INS 10000000\n")
        f.write("\n")

        f.write("# Load nonce\n")
        if ((len(ad)==0) and (len(ct)==0)): f.write("INS 41{:06x}\n".format(len(npub)))
        else: f.write("INS 40{:06x}\n".format(len(npub)))
        write_data_seg(f, npub, len(npub))

        if len(ad) > 0:
            f.write("# Load associated data\n")
            if (len(ct)==0): f.write("INS 51{:06x}\n".format(len(ad)))
            else: f.write("INS 50{:06x}\n".format(len(ad)))
            write_data_seg(f, ad, len(ad))

        if (len(ct)>0):
            f.write("# Load ciphertext\n")
            f.write("INS 71{:06X}\n".format(len(ct)))
            write_data_seg(f, ct, len(ct))

        f.write("\n# Load tag\n")
        f.write("INS 81{:06x}\n".format(16))
        write_data_seg(f, tag, 16)

    if INCL_HASH:
        f.write("# Specify hashing\n")
        f.write("INS 20000000\n")
        f.write("\n")

        f.write("# Load message data\n")
        f.write("INS 51{:06x}\n".format(len(msg)))
        write_data_seg(f, msg, len(msg))

    f.close()


def run_tb(key, npub, ad, pt, variant):
    """
    Pad inputs, generate a test vector file, and run verilog test bench
    """
    # Compute Ascon in software
    ct, tag = ascon_encrypt(key, npub, ad, pt)
    hash = ascon_hash(ad)

    # Compute Ascon in hardware
    ad = bytearray(ad)
    pt = bytearray(pt)
    msg = bytearray(ad)

    # Write test vector file for verilog test bench to "tv/tv.txt"
    write_tv_file(key, npub, ad, pt, ct, tag, msg)

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
    hw_pt = bytearray()
    hw_hash = bytearray()
    hw_auth = bytearray()
    for line in stdout.readlines():
        if "pt   =>" in line:
            hw_pt += bytearray.fromhex(line[8 : 8 + 16])
        if "ct   =>" in line:
            hw_ct += bytearray.fromhex(line[8 : 8 + 16])
        if "tag  =>" in line:
            hw_tag += bytearray.fromhex(line[8 : 8 + 16])
        if "hash =>" in line:
            hw_hash += bytearray.fromhex(line[8 : 8 + 16])
        if "auth =>" in line:
            hw_auth += bytearray.fromhex("0" + line[8 : 8 + 1])
    
    # Truncate hw outputs to expected length
    hw_pt = hw_pt[0:len(pt)]
    hw_ct = hw_ct[0:len(ct)]

    print("ad   = " + "".join("{:02x}".format(x) for x in ad))
    print("pt   = " + "".join("{:02x}".format(x) for x in pt))
    print("ct   = " + "".join("{:02x}".format(x) for x in ct))
    print("tag  = " + "".join("{:02x}".format(x) for x in tag))
    print("msg  = " + "".join("{:02x}".format(x) for x in msg))
    print("hash = " + "".join("{:02x}".format(x) for x in hash))

    # Compare test bench output to software implementation
    result = 0
    if INCL_ENC:
        check_result("ct", ct, hw_ct)
    if INCL_DEC:
        check_result("pt", pt, hw_pt)
        if (hw_auth[0] != 1):
            print(f"{FAIL}")
            print("tag verification")
            print(f"ERROR{ENDC}")
            exit()
    if INCL_HASH:
        check_result("hash", hash, hw_hash)


# Generate one test vector and run test bench
def run_hw_single(variant):
    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    npub = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    ad = bytes.fromhex("")
    pt = bytes.fromhex("")
    print(variant)
    print("key  = " + "".join("{:02x}".format(x) for x in key))
    print("npub = " + "".join("{:02x}".format(x) for x in npub))
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
