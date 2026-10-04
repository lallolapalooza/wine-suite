#!/usr/bin/env python3
"""Carve a header-only ZIP fragment out of a larger file and extract every entry.

The SDA installer carries a 10k-entry deflate ZIP with NO end-of-central-directory record, so
zipfile cannot open it. Every entry does have a PK\\x03\\x04 local header; when the "sizes in
data descriptor" flag (0x08) is set, the compressed size in the header is zero and the real
boundary is the next local header. So: walk the sorted list of all local-header offsets, and
inflate each slice with a decompressobj, discarding unused_data.

usage: extract_vfs.py <file> <outdir> [--dump-list list.txt]
"""
import os
import struct
import sys
import zlib

LOCAL = b"PK\x03\x04"


def find_all(data, sig):
    out = []
    i = 0
    while True:
        i = data.find(sig, i)
        if i < 0:
            return out
        out.append(i)
        i += 1


def main():
    path, outdir = sys.argv[1], sys.argv[2]
    data = open(path, "rb").read()
    offs = find_all(data, LOCAL)
    print("local headers:", len(offs))
    os.makedirs(outdir, exist_ok=True)

    names = []
    n_extract = 0
    n_fail = 0
    for idx, off in enumerate(offs):
        (ver, flags, method, mtime, mdate, crc, csize, usize,
         nlen, elen) = struct.unpack_from("<HHHHHIIIHH", data, off + 4)
        raw_name = data[off + 30:off + 30 + nlen]
        name = raw_name.decode("utf-8", "replace")
        dstart = off + 30 + nlen + elen
        end = offs[idx + 1] if idx + 1 < len(offs) else len(data)
        if csize and dstart + csize <= end:
            end = dstart + csize
        blob = data[dstart:end]
        names.append(name)
        if name.endswith("/"):
            os.makedirs(os.path.join(outdir, name), exist_ok=True)
            continue
        try:
            if method == 0:
                payload = blob[:usize] if usize else blob
            elif method == 8:
                d = zlib.decompressobj(-15)
                payload = d.decompress(blob)
                payload += d.flush()
            else:
                n_fail += 1
                continue
        except Exception:
            n_fail += 1
            continue
        dest = os.path.join(outdir, name)
        try:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as f:
                f.write(payload)
            n_extract += 1
        except Exception:
            n_fail += 1

    print("extracted: %d  failed: %d" % (n_extract, n_fail))
    if "--dump-list" in sys.argv:
        with open(sys.argv[sys.argv.index("--dump-list") + 1], "w") as f:
            f.write("\n".join(names) + "\n")


if __name__ == "__main__":
    main()
