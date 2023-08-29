#!/usr/bin/env python3
#
# Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
# for details.
#
# Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
#
# Software implementation of Ascon-128. Associated data (ad) and plaintext (p)
# need to be 10*-padded to a multiple of the block size (64-bits).

debugpermutation = False


def ascon_aead(variant, k, n, ad, p, debug_perm):
    global debugpermutation
    debugpermutation = debug_perm
    c = ascon_encrypt(k, n, ad, p)
    return c


def ascon_encrypt(key, nonce, ad, p, variant="Ascon-128"):
    S = [0, 0, 0, 0, 0]
    k = len(key) * 8  # bits
    a = 12  # rounds
    b = 8 if variant == "Ascon-128a" else 6  # rounds
    rate = 16 if variant == "Ascon-128a" else 8  # bytes
    ascon_initialize(S, k, rate, a, b, key, nonce)
    ascon_process_associated_data(S, b, rate, ad)
    c = ascon_process_plaintext(S, b, rate, p)
    tag = ascon_finalize(S, rate, a, key)
    return c + tag


def ascon_decrypt(key, nonce, ad, c, variant="Ascon-128"):
    S = [0, 0, 0, 0, 0]
    k = len(key) * 8  # bits
    a = 12  # rounds
    b = 8 if variant == "Ascon-128a" else 6  # rounds
    rate = 16 if variant == "Ascon-128a" else 8  # bytes
    ascon_initialize(S, k, rate, a, b, key, nonce)
    ascon_process_associated_data(S, b, rate, ad)
    p = ascon_process_ciphertext(S, b, rate, c[:-16])
    tag = ascon_finalize(S, rate, a, key)
    if tag == c[-16:]:
        return p
    else:
        return None


def ascon_initialize(S, k, rate, a, b, key, nonce):
    iv_zero_key_nonce = (
        to_bytes([k, rate * 8, a, b] + (20 - len(key)) * [0]) + key + nonce
    )
    S[0], S[1], S[2], S[3], S[4] = bytes_to_state(iv_zero_key_nonce)
    ascon_permutation(S, a)
    zero_key = bytes_to_state(zero_bytes(40 - len(key)) + key)
    S[0] ^= zero_key[0]
    S[1] ^= zero_key[1]
    S[2] ^= zero_key[2]
    S[3] ^= zero_key[3]
    S[4] ^= zero_key[4]


def ascon_process_associated_data(S, b, rate, ad):
    if len(ad) > 0:
        for block in range(0, len(ad), rate):
            S[0] ^= bytes_to_int(ad[block : block + 8])
            if rate == 16:
                S[1] ^= bytes_to_int(ad[block + 8 : block + 16])
            ascon_permutation(S, b)
    S[4] ^= 1


def ascon_process_plaintext(S, b, rate, p):
    c = to_bytes([])
    for block in range(0, len(p), rate):
        if rate == 8:
            S[0] ^= bytes_to_int(p[block : block + 8])
            c += int_to_bytes(S[0], 8)
        elif rate == 16:
            S[0] ^= bytes_to_int(p[block : block + 8])
            S[1] ^= bytes_to_int(p[block + 8 : block + 16])
            c += int_to_bytes(S[0], 8) + int_to_bytes(S[1], 8)
        if block < (len(p) - rate):
            ascon_permutation(S, b)
    return c


def ascon_process_ciphertext(S, b, rate, c):
    p = to_bytes([])
    for block in range(0, len(c), rate):
        if rate == 8:
            Ci = bytes_to_int(c[block : block + 8])
            p += int_to_bytes(S[0] ^ Ci, 8)
            S[0] = Ci
        elif rate == 16:
            Ci = (
                bytes_to_int(c[block : block + 8]),
                bytes_to_int(c[block + 8 : block + 16]),
            )
            p += int_to_bytes(S[0] ^ Ci[0], 8) + int_to_bytes(S[1] ^ Ci[1], 8)
            S[0] = Ci[0]
            S[1] = Ci[1]
        if block < (len(p) - rate):
            ascon_permutation(S, b)
    return p


def ascon_finalize(S, rate, a, key):
    assert len(key) in [16, 20]
    S[rate // 8 + 0] ^= bytes_to_int(key[0:8])
    S[rate // 8 + 1] ^= bytes_to_int(key[8:16])
    S[rate // 8 + 2] ^= bytes_to_int(key[16:] + zero_bytes(24 - len(key)))

    ascon_permutation(S, a)

    S[3] ^= bytes_to_int(key[-16:-8])
    S[4] ^= bytes_to_int(key[-8:])
    tag = int_to_bytes(S[3], 8) + int_to_bytes(S[4], 8)
    return tag


def ascon_permutation(S, rounds=1):
    assert rounds <= 12
    if debugpermutation:
        printwords(S, "permutation input:")
    for r in range(12 - rounds, 12):
        # --- add round constants ---
        S[2] ^= 0xF0 - r * 0x10 + r * 0x1
        # --- substitution layer ---
        S[0] ^= S[4]
        S[4] ^= S[3]
        S[2] ^= S[1]
        T = [(S[i] ^ 0xFFFFFFFFFFFFFFFF) & S[(i + 1) % 5] for i in range(5)]
        for i in range(5):
            S[i] ^= T[(i + 1) % 5]
        S[1] ^= S[0]
        S[0] ^= S[4]
        S[3] ^= S[2]
        S[2] ^= 0xFFFFFFFFFFFFFFFF
        # --- linear diffusion layer ---
        S[0] ^= rotr(S[0], 19) ^ rotr(S[0], 28)
        S[1] ^= rotr(S[1], 61) ^ rotr(S[1], 39)
        S[2] ^= rotr(S[2], 1) ^ rotr(S[2], 6)
        S[3] ^= rotr(S[3], 10) ^ rotr(S[3], 17)
        S[4] ^= rotr(S[4], 7) ^ rotr(S[4], 41)
    if debugpermutation:
        printwords(S, "permutation output:")


def zero_bytes(n):
    return n * b"\x00"


def to_bytes(l):
    return bytes(bytearray(l))


def bytes_to_int(bytes):
    return sum(
        [bi << ((len(bytes) - 1 - i) * 8) for i, bi in enumerate(to_bytes(bytes))]
    )


def bytes_to_state(bytes):
    return [bytes_to_int(bytes[8 * w : 8 * (w + 1)]) for w in range(5)]


def int_to_bytes(integer, nbytes):
    return to_bytes([(integer >> ((nbytes - 1 - i) * 8)) % 256 for i in range(nbytes)])


def rotr(val, r):
    return (val >> r) | ((val & (1 << r) - 1) << (64 - r))


def printwords(S, description=""):
    print(" " + description)
    print("\n".join(["  x{i}={s:016X}".format(**locals()) for i, s in enumerate(S)]))


if __name__ == "__main__":
    k = bytearray.fromhex("000102030405060708090a0b0c0d0e0f")
    n = bytearray.fromhex("000102030405060708090a0b0c0d0e0f")
    ad = bytearray.fromhex("00010203")
    p = bytearray.fromhex("00010203")
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
    print("c      = " + "".join("{:02x}".format(x) for x in c[:-16]))
    print("tag    = " + "".join("{:02x}".format(x) for x in c[-16:]))
