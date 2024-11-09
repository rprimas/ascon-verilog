#!/usr/bin/env python3
#
# Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
# for details.
#
# Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
#
# Software implementation of Ascon-128a.

DEBUG = True

def ascon_aead(key, npub, ad, pt, debug):
    """
    Ascon-128a authenticated encryption and decryption.

    :param key: Key with length of 16 bytes
    :param npub: Nonce with length of 16 bytes
    :param ad: Associated data. Needs to be 10*-padded so length is a multiple of 4 (unless original length is 0)
    :param pt: Plaintext. Needs to be 10*-padded so length is a multiple of 4 (even if original length is 0)

    :return: Ciphertext with same length as padded pt and 16 byte tag.
    """ 
    global DEBUG
    DEBUG = False
    assert(len(key) == 16)
    assert(len(npub) == 16)
    assert((len(ad)==0) or (len(ad)%4) == 0)
    assert((len(ad)%4) == 0)
    ct, tag = ascon_encrypt(key, npub, ad, pt)
    pt2 = ascon_decrypt(key, npub, ad, ct, tag)
    assert(pt2 is not None)
    return ct, tag


def ascon_encrypt(key, npub, ad, pt):
    S = [0, 0, 0, 0, 0]
    k = len(key) * 8
    a = 12
    b = 8
    rate = 16
    ascon_initialize(S, k, rate, a, b, key, npub)
    ascon_process_associated_data(S, b, rate, ad)
    ct = ascon_process_plaintext(S, b, rate, pt)
    tag = ascon_finalize(S, rate, a, key)
    return ct, tag


def ascon_decrypt(key, npub, ad, ct, tag):
    S = [0, 0, 0, 0, 0]
    k = len(key) * 8
    a = 12
    b = 8
    rate = 16
    ascon_initialize(S, k, rate, a, b, key, npub)
    ascon_process_associated_data(S, b, rate, ad)
    pt = ascon_process_ciphertext(S, b, rate, ct)
    tag2 = ascon_finalize(S, rate, a, key)
    if tag == tag2:
        return pt
    else:
        print("no match")
        return None


def ascon_hash(m, debug):
    global DEBUG
    DEBUG = debug
    a = 12
    b = 12
    rate = 8
    hash_length = 32
    tag_spec = int_to_bytes(256, 4)
    S = bytes_to_state(to_bytes([0, rate * 8, a, a - b]) + tag_spec + zero_bytes(32))
    ascon_permutation(S, a)
    for block in range(0, len(m) - rate, rate):
        S[0] ^= bytes_to_int(m[block : block + 8])
        ascon_permutation(S, b)
    block = len(m) - rate
    S[0] ^= bytes_to_int(m[block : block + 8])
    H = b""
    ascon_permutation(S, a)
    while len(H) < hash_length:
        H += int_to_bytes(S[0], 8)
        ascon_permutation(S, b)
    return H[:hash_length]


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
    return c[0:len(p)]


def ascon_process_ciphertext(S, b, rate, c):
    p = to_bytes([])
    bytes_rem = len(c)
    print("bytes_rem " + str(bytes_rem))
    for block in range(0, len(c), rate):
        if rate == 8:
            Ci = bytes_to_int(c[block : block + 8])
            p += int_to_bytes(S[0] ^ Ci, 8)
            S[0] = Ci
        elif rate == 16:
            Ci = (
                bytes_to_int(c[block + 0 : block + 4]),
                bytes_to_int(c[block + 4 : block + 8]),
                bytes_to_int(c[block + 8 : block + 12]),
                bytes_to_int(c[block + 12 : block + 16])
            )
            p += int_to_bytes(S[0]^((Ci[0]<<32)+(Ci[1])),8)
            p += int_to_bytes(S[1]^((Ci[2]<<32)+(Ci[3])),8)
            print(p)
            if (bytes_rem > 0):
                S[0] = (S[0] & 0x00000000FFFFFFFF) | (Ci[0]<<32)
                bytes_rem -= 4
                print("1")
            if (bytes_rem > 0):
                S[0] = (S[0] & 0xFFFFFFFF00000000) | (Ci[1])
                bytes_rem -= 4
                print("2")
            if (bytes_rem > 0):
                S[1] = (S[1] & 0x00000000FFFFFFFF) | (Ci[2]<<32)
                bytes_rem -= 4
                print("3")
            if (bytes_rem > 0):
                S[1] = (S[1] & 0xFFFFFFFF00000000) | (Ci[3])
                bytes_rem -= 4
                print("4")
        if block < (len(p) - rate):
            ascon_permutation(S, b)
    return p[0:len(c)]


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
    if DEBUG:
        print_words(S, f"\n{rounds} rounds, input:")
    for r in range(12 - rounds, 12):
        S[2] ^= 0xF0 - r * 0x10 + r * 0x1
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
        S[0] ^= rotr(S[0], 19) ^ rotr(S[0], 28)
        S[1] ^= rotr(S[1], 61) ^ rotr(S[1], 39)
        S[2] ^= rotr(S[2], 1) ^ rotr(S[2], 6)
        S[3] ^= rotr(S[3], 10) ^ rotr(S[3], 17)
        S[4] ^= rotr(S[4], 7) ^ rotr(S[4], 41)
    if DEBUG:
        print_words(S, "output:")


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


def print_words(S, description=""):
    print(" " + description)
    print("\n".join(["  x{i}={s:016X}".format(**locals()) for i, s in enumerate(S)]))


if __name__ == "__main__":
    key = bytearray.fromhex("000102030405060708090a0b0c0d0e0f")
    npub = bytearray.fromhex("000102030405060708090a0b0c0d0e0f")
    ad = bytearray.fromhex("000102")
    pt = bytearray.fromhex("000102")

    ad_pad = bytearray(ad)
    pt_pad = bytearray(pt)

    # 10*-pad inputs to block size (64 bits)
    if len(ad_pad) > 0:
        ad_pad.append(0x80)
        while len(ad_pad) % 8 != 0:
            ad_pad.append(0x00)
    pt_pad.append(0x80)
    while len(pt_pad) % 8 != 0:
        pt_pad.append(0x00)

    # hash input is same as pt
    msg_pad = pt_pad.copy()

    # Compute Ascon in software
    ct, tag = ascon_aead(key, npub, ad_pad, pt_pad, 0)
    hash = ascon_hash(msg_pad, 0)

    print("key  = " + "".join("{:02x}".format(x) for x in key))
    print("npub = " + "".join("{:02x}".format(x) for x in npub))
    print("ad   = " + "".join("{:02x}".format(x) for x in ad_pad))
    print("pt   = " + "".join("{:02x}".format(x) for x in pt_pad))
    print("ct   = " + "".join("{:02x}".format(x) for x in ct))
    print("tag  = " + "".join("{:02x}".format(x) for x in tag))
    print("msg  = " + "".join("{:02x}".format(x) for x in msg_pad))
    print("hash = " + "".join("{:02x}".format(x) for x in hash))
