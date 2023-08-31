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
# 3. compares the test bench output to an Ascon osoftware implementation

import argparse, io, os, subprocess
from ascon import *

# Terminal color codescore
OKGREEN = "\033[92m"
WARNING = "\033[93m"
FAIL = "\033[91m"
ENDC = "\033[0m"

# Specify encryption, decryption, and/or hash operations for the Ascon core
INCL_ENC = 1
INCL_DEC = 1
INCL_HASH = 1


# Print inputs/outputs of Ascon software implementation
def print_result(result, ad_pad, p_pad, c, m_pad, h):
    if result:
        print(f"{FAIL}")
    print("ad = " + "".join("{:02x}".format(x) for x in ad_pad))
    print("p  = " + "".join("{:02x}".format(x) for x in p_pad))
    print("c  = " + "".join("{:02x}".format(x) for x in c[:-16]))
    print("t  = " + "".join("{:02x}".format(x) for x in c[-16:]))
    print("m  = " + "".join("{:02x}".format(x) for x in m_pad))
    print("h  = " + "".join("{:02x}".format(x) for x in h))
    if result:
        print(f"ERROR{ENDC}")
    else:
        print(f"{OKGREEN}PASS{ENDC}")


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
def write_tv_file(k, n, ad, p, c, m):
    f = open("tv/tv.txt", "w")

    if INCL_ENC:
        f.write("# Load key\n")
        f.write("INS 30{:06x}\n".format(len(k)))
        write_data_seg(f, k, len(k))

        f.write("# Specify authenticated encryption\n")
        f.write("INS 00000000\n")
        f.write("\n")

        f.write("# Load nonce\n")
        f.write("INS 40{:06x}\n".format(len(n)))
        write_data_seg(f, n, len(n))

        if len(ad) > 0:
            f.write("# Load associated data\n")
            f.write("INS 50{:06x}\n".format(len(ad)))
            write_data_seg(f, ad, len(ad))

        f.write("# Load plaintext\n")
        f.write("INS 61{:06X}\n".format(len(p)))
        write_data_seg(f, p, len(p))

    if INCL_DEC:
        if not INCL_ENC:
            f.write("# Load key\n")
            f.write("INS 30{:06x}\n".format(len(k)))
            write_data_seg(f, k, len(k))

        f.write("# Specify authenticated decryption\n")
        f.write("INS 10000000\n")
        f.write("\n")

        f.write("# Load nonce\n")
        f.write("INS 40{:06x}\n".format(len(n)))
        write_data_seg(f, n, len(n))

        if len(ad) > 0:
            f.write("# Load associated data\n")
            f.write("INS 50{:06x}\n".format(len(ad)))
            write_data_seg(f, ad, len(ad))

        f.write("# Load ciphertext\n")
        f.write("INS 71{:06X}\n".format(len(p)))
        write_data_seg(f, c, len(c) - 16)

        f.write("# Load tag\n")
        f.write("INS 81{:06x}\n".format(16))
        write_data_seg(f, c[-16:], 16)

    if INCL_HASH:
        f.write("# Specify hashing\n")
        f.write("INS 20000000\n")
        f.write("\n")

        f.write("# Load message data\n")
        f.write("INS 51{:06x}\n".format(len(m)))
        write_data_seg(f, m, len(m))

    f.close()


# Pad inputs, generate a test vector file, and run verilog test bench
def run_tb(k, n, ad, p):
    ad_pad = bytearray(ad)
    p_pad = bytearray(p)
    m_pad = bytearray(ad)

    # 10*-pad inputs to block size (64 bits)
    if len(ad_pad) > 0:
        ad_pad.append(0x80)
        while len(ad_pad) % 8 != 0:
            ad_pad.append(0x00)
    p_pad.append(0x80)
    while len(p_pad) % 8 != 0:
        p_pad.append(0x00)
    m_pad.append(0x80)
    while len(m_pad) % 8 != 0:
        m_pad.append(0x00)

    # Compute Ascon in software
    c = ascon_aead("Ascon-128", k, n, ad_pad, p_pad, 0)
    h = ascon_hash(m_pad)

    # Write test vector file for verilog test bench
    write_tv_file(k, n, ad_pad, p_pad, c, m_pad)

    # Run verilog test bench and parse the output
    ps = subprocess.run(
        ["make"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, text=True
    )
    stdout = io.StringIO(ps.stdout)
    tb_c = bytearray()
    tb_t = bytearray()
    tb_p = bytearray()
    tb_h = bytearray()
    tb_ver = bytearray()
    for line in stdout.readlines():
        if "c =>" in line:
            tb_c += bytearray.fromhex(line[5 : 5 + 16])
        if "t =>" in line:
            tb_t += bytearray.fromhex(line[5 : 5 + 16])
        if "p =>" in line:
            tb_p += bytearray.fromhex(line[5 : 5 + 16])
        if "h =>" in line:
            tb_h += bytearray.fromhex(line[5 : 5 + 16])
        if "v =>" in line:
            tb_ver += bytearray.fromhex("0" + line[5 : 5 + 1])

    # Compare test bench output to software implementation
    result = 0
    if INCL_ENC:
        result |= c[:-16] != tb_c
        result |= c[-16:] != tb_t
    if INCL_DEC:
        result |= p_pad != tb_p
        result |= tb_ver[0] != 1
    if INCL_HASH:
        result |= h != tb_h
    print_result(result, ad_pad, p_pad, c, m_pad, h)


# Generate one test vector and run test bench
def run_tb_single():
    k = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    n = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    ad = bytes.fromhex("")
    p = bytes.fromhex("00010203")
    print("k      = " + "".join("{:02x}".format(x) for x in k))
    print("n      = " + "".join("{:02x}".format(x) for x in n))
    run_tb(k, n, ad, p)
    print(f"{OKGREEN}ALL PASS{ENDC}")


# Generate multiple test vectors and run test bench
def run_tb_sweep():
    klen = 16
    nlen = 16
    k = to_bytes(os.urandom(klen))
    n = to_bytes(os.urandom(nlen))
    print("k      = " + "".join("{:02x}".format(x) for x in k))
    print("n      = " + "".join("{:02x}".format(x) for x in n))
    for adlen in range(16):
        for plen in range(16):
            ad = bytearray(os.urandom(adlen))
            p = bytearray(os.urandom(plen))
            run_tb(k, n, ad, p)
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
    args = parser.parse_args()
    if args.single is not None:
        run_tb_single()
    else:
        run_tb_sweep()
