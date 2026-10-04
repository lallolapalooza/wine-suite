#!/usr/bin/env python3
"""Resolve a PE virtual address to module + RVA + section using a /proc/pid/maps dump.

usage: resolve_addr.py <maps.txt> <hexaddr> [<hexaddr> ...]
"""
import subprocess, sys, os

maps_path = sys.argv[1]
addrs = [int(a, 16) for a in sys.argv[2:]]

entries = []
for line in open(maps_path):
    parts = line.rstrip("\n").split(None, 5)
    if len(parts) < 6:
        continue
    start, end = parts[0].split("-")
    off = int(parts[2], 16)
    path = parts[5]
    entries.append((int(start, 16), int(end, 16), off, parts[1], path))

# module base = lowest mapping start for a given file (Wine maps PE at its preferred base)
bases = {}
for s, e, off, perms, path in entries:
    if not path.startswith("/"):
        continue
    b = bases.get(path)
    if b is None or s - off < b:
        bases[path] = s - off

sec_cache = {}
def sections(path):
    if path in sec_cache:
        return sec_cache[path]
    out = []
    try:
        txt = subprocess.run(["objdump", "-h", path], capture_output=True, text=True).stdout
    except Exception:
        txt = ""
    for ln in txt.splitlines():
        f = ln.split()
        if len(f) >= 7 and f[0].isdigit():
            # Idx Name Size VMA LMA File off Algn
            try:
                name = f[1]
                size = int(f[2], 16)
                vma = int(f[3], 16)
                foff = int(f[5], 16)
                out.append((name, vma, size, foff))
            except ValueError:
                pass
    sec_cache[path] = out
    return out

for a in addrs:
    hit = None
    for s, e, off, perms, path in entries:
        if s <= a < e:
            hit = (s, e, off, perms, path)
            break
    if not hit:
        print("%016x -> (unmapped)" % a)
        continue
    s, e, off, perms, path = hit
    if not path.startswith("/"):
        print("%016x -> [%s] %s" % (a, perms, path))
        continue
    base = bases[path]
    rva = a - base
    sec = ""
    for name, vma, size, foff in sections(path):
        if vma <= rva < vma + size:
            sec = "%s+0x%x" % (name, rva - vma)
            break
    print("%016x -> %-40s base=%016x rva=0x%x %s" %
          (a, os.path.basename(path), base, rva, sec))
