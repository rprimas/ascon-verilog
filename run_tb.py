#!/usr/bin/env python3
#
# Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
# for details.
#
# Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
#
# This file contains python scripts that automatically generate test vectors,
# run verilog testbenches, and compare the resulting output to a software
# implementation.

import argparse
import os
import subprocess
from ascon import *

# Terminal color codescore
OKGREEN = "\033[92m"
WARNING = "\033[93m"
FAIL = "\033[91m"
ENDC = "\033[0m"

# Specify encryption and/or decryption operations for the Ascon core
DO_ENC = 1
DO_DEC = 1


# Print inputs/outputs of Ascon software implementation
def print_ascon(ad, ad_pad, m, m_pad, c, event):
    if event == "fail":
        print(f"{FAIL}")
    print("ad     = " + "".join("{:02x}".format(x) for x in ad))
    print("ad_pad = " + "".join("{:02x}".format(x) for x in ad_pad))
    print("m      = " + "".join("{:02x}".format(x) for x in m))
    print("m_pad  = " + "".join("{:02x}".format(x) for x in m_pad))
    print("c      = " + "".join("{:02x}".format(x) for x in c[:-16]))
    print("tag    = " + "".join("{:02x}".format(x) for x in c[-16:]))
    if event == "pass":
        print(f"{OKGREEN}PASS{ENDC}")
    if event == "fail":
        print("ERROR")
    print(f"{ENDC}")


# Write data segment to KAT file
def write_data_seg(f, x, xlen):
    for i in range(xlen):
        if (i % 4) == 0:
            f.write("DAT ")
        f.write("{:02X}".format(x[i]))
        if (i % 4) == 3:
            f.write("\n")
    f.write("\n")


# Write known answer test (KAT) file
def write_kat_file(k, klen, n, nlen, ad, adlen, m, c, mlen):
    f = open("KAT/KAT_tmp.txt", "w")

    f.write("# Load key\n")
    f.write("INS 30{:06x}\n".format(klen))
    write_data_seg(f, k, klen)

    if DO_ENC:
        f.write("# Specify authenticated encryption\n")
        f.write("INS 00000000\n")
        f.write("\n")

        f.write("# Load nonce\n")
        f.write("INS 4{:01x}{:06x}\n".format(not (adlen or mlen), nlen))
        write_data_seg(f, n, nlen)

        if adlen > 0:
            f.write("# Load associated data\n")
            f.write("INS 5{:01x}{:06x}\n".format(not (mlen), adlen))
            write_data_seg(f, ad, adlen)

        if mlen > 0:
            f.write("# Load message\n")
            f.write("INS 61{:06X}\n".format(mlen))
            write_data_seg(f, m, mlen)

    if DO_DEC:
        f.write("# Specify authenticated decryption\n")
        f.write("INS 10000000\n")
        f.write("\n")

        f.write("# Load nonce\n")
        f.write("INS 4{:01x}{:06x}\n".format(not (adlen or mlen), nlen))
        write_data_seg(f, n, nlen)

        if adlen > 0:
            f.write("# Load associated data\n")
            f.write("INS 5{:01x}{:06x}\n".format(not (mlen), adlen))
            write_data_seg(f, ad, adlen)

        if mlen > 0:
            f.write("# Load message\n")
            f.write("INS 61{:06X}\n".format(mlen))
            write_data_seg(f, c, mlen)

        f.write("# Load tag\n")
        f.write("INS 71{:06x}\n".format(16))
        write_data_seg(f, c[-16:], 16)

    f.close()


# Pad inputs, generate a KAT file, and run verilog testbench
def run_tb(k, n, ad, p):
    ad_pad = bytearray(ad)
    p_pad = bytearray(p)

    # 10*-pad inputs to block size (64 bits)
    if len(ad_pad) > 0:
        ad_pad.append(0x80)
        while len(ad_pad) % 8 != 0:
            ad_pad.append(0x00)
    p_pad.append(0x80)
    while len(p_pad) % 8 != 0:
        p_pad.append(0x00)

    # Compute Ascon in software
    c = ascon_aead("Ascon-128", k, n, ad_pad, p_pad, 0)

    # Write KAT file for verilog testbench
    write_kat_file(k, len(k), n, len(n), ad_pad, len(ad_pad), p_pad, c, len(p_pad))

    # Run verilog testbench and grep the output
    try:
        ps = subprocess.Popen(["make"], stdout=subprocess.PIPE)
        result = subprocess.check_output((["grep", "-e", "=>"]), stdin=ps.stdout)
    except:
        print(f"{FAIL}EXECUTION ERROR{ENDC}")

    # Compare Ascon computation between hardware/software
    if DO_ENC and DO_DEC:
        out_len = len(p_pad) + 16 + len(p_pad)
        ref_sw = c + p_pad
    elif DO_ENC:
        out_len = len(p_pad) + 16
        ref_sw = c
    elif DO_DEC:
        out_len = len(p_pad)
        ref_sw = p_pad
    for i in range(out_len):
        x_sw = ref_sw[i]
        offset = 7 + (i // 4) * 16 + (i % 4) * 2
        x_hw = bytearray.fromhex(result[offset : offset + 2].decode())[0]
        if x_sw != x_hw:
            print_ascon(ad, ad_pad, p, p_pad, c, "fail")
            exit()
    if DO_DEC:
        msg_auth = bytearray.fromhex("0" + result[-2:-1].decode())
        if msg_auth == 0:
            print_ascon(ad, ad_pad, p, p_pad, c, "fail")
            exit()
    print_ascon(ad, ad_pad, p, p_pad, c, "pass")


# Generate one test vector and run testbench
def run_tb_single():
    # k = to_bytes(os.urandom(16))
    # n = to_bytes(os.urandom(16))
    # ad = bytearray(os.urandom(16))
    # p = bytearray(os.urandom(16))
    k = bytearray.fromhex("000102030405060708090a0b0c0d0e0f")
    n = bytearray.fromhex("000102030405060708090a0b0c0d0e0f")
    ad = bytearray.fromhex("00010203")
    p = bytearray.fromhex("00010203")
    print("k      = " + "".join("{:02x}".format(x) for x in k))
    print("n      = " + "".join("{:02x}".format(x) for x in n))
    run_tb(k, n, ad, p)
    print(f"{OKGREEN}ALL PASS{ENDC}")


# Generate multiple test vectors and run testbench
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
        help="Perform a single testbench run.",
    )
    parser.add_argument(
        "-w",
        "--sweep",
        action="store",
        nargs="*",
        help="Sweep over inputs of different lengths and perform testbench runs.",
    )
    args = parser.parse_args()
    if args.single is not None:
        run_tb_single()
    else:
        run_tb_sweep()
