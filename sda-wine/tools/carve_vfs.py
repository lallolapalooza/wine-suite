#!/usr/bin/env python3
"""Carve and list/extract the embedded archive inside a Tcl/Tk-packaged Windows PE.

Handles two cases:
  * a well-formed ZIP (EOCD present) -> extract with the stdlib zipfile
  * a header-only ZIP fragment (no central directory) -> walk PK\\x03\\x04 local headers

usage: carve_vfs.py <pe-file> [--extract DIR]
"""
import os
import struct
import sys
import zlib

LOCAL = b"PK\x03\x04"
CENTRAL = b"PK\x01\x02"
EOCD = b"PK\x05\x06"


def find_all(data, sig):
    out = []
    i = 0
    while True:
        i = data.find(sig, i)
        if i < 0:
            return out
        out.append(i)
        i += 1


def walk_local_headers(data, start):
    """Sequentially parse local file headers starting at `start`."""
    entries = []
    off = start
    while off + 30 <= len(data):
        if data[off:off + 4] != LOCAL:
            break
        (ver, flags, method, mtime, mdate, crc, csize, usize,
         nlen, elen) = struct.unpack_from("<HHHHHIIIHH", data, off + 4)
        name = data[off + 30:off + 30 + nlen]
        try:
            name = name.decode("utf-8", "replace")
        except Exception:
            name = repr(name)
        dstart = off + 30 + nlen + elen
        blob = data[dstart:dstart + csize]
        entries.append(dict(off=off, name=name, method=method, flags=flags,
                            csize=csize, usize=usize, crc=crc, blob=blob))
        if flags & 0x08 and csize == 0:
            break  # sizes in a trailing data descriptor: cannot walk further
        off = dstart + csize
    return entries


def main():
    path = sys.argv[1]
    extract = None
    if "--extract" in sys.argv:
        extract = sys.argv[sys.argv.index("--extract") + 1]
    data = open(path, "rb").read()
    print("file size", len(data))
    for sig, name in ((LOCAL, "local"), (CENTRAL, "central"), (EOCD, "eocd")):
        hits = find_all(data, sig)
        print("%-8s %6d  first=%s last=%s" % (name, len(hits), hits[:3], hits[-3:]))

    eocd = find_all(data, EOCD)
    if eocd:
        e = eocd[-1]
        cdir_size, cdir_off = struct.unpack_from("<II", data, e + 12)
        total = struct.unpack_from("<H", data, e + 10)[0]
        print("EOCD: entries=%d cdir_off=%d cdir_size=%d" % (total, cdir_off, cdir_size))
        import zipfile
        base = data.find(LOCAL)
        end = e + 22
        raw = data[base:end]
        tmp = path + ".carved.zip"
        open(tmp, "wb").write(raw)
        z = zipfile.ZipFile(tmp)
        print("zipfile entries:", len(z.namelist()))
        for n in z.namelist()[:200]:
            print("  ", n, z.getinfo(n).file_size)
        if extract:
            z.extractall(extract)
            print("extracted to", extract)
        return

    first = data.find(LOCAL)
    if first < 0:
        print("no local header found")
        return
    print("first local header at", first)
    entries = walk_local_headers(data, first)
    print("walked %d entries" % len(entries))
    for e in entries[:400]:
        print("  %-60s method=%d csize=%-9d usize=%d" % (e["name"], e["method"], e["csize"], e["usize"]))
    if extract:
        os.makedirs(extract, exist_ok=True)
        for e in entries:
            dest = os.path.join(extract, e["name"])
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            if e["method"] == 0:
                payload = e["blob"]
            elif e["method"] == 8:
                try:
                    payload = zlib.decompress(e["blob"], -15)
                except Exception as ex:
                    print("  ! inflate failed", e["name"], ex)
                    continue
            else:
                print("  ! unsupported method", e["method"], e["name"])
                continue
            open(dest, "wb").write(payload)
        print("extracted to", extract)


if __name__ == "__main__":
    main()
