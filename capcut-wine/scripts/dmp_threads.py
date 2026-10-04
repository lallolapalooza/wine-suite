#!/usr/bin/env python3
"""List every thread in a (crashpad) minidump with its RIP mapped to module+offset, and scan each
thread's stack for return addresses into modules -- i.e. a usable call chain without symbols.

usage: dmp_threads.py <dump> [--per-thread N] [--threads K]
"""
import sys
import struct

from minidump.minidumpfile import MinidumpFile

path = sys.argv[1]
per_thread = 12
max_threads = 8
if "--per-thread" in sys.argv:
    per_thread = int(sys.argv[sys.argv.index("--per-thread") + 1])
if "--threads" in sys.argv:
    max_threads = int(sys.argv[sys.argv.index("--threads") + 1])

mf = MinidumpFile.parse(path)
mods = sorted(mf.modules.modules, key=lambda m: m.baseaddress)


def mod_for(addr):
    for m in mods:
        if m.baseaddress <= addr < m.baseaddress + (m.size or 0):
            return m, addr - m.baseaddress
    return None, None


def name_of(m):
    n = m.name or "?"
    return n.replace("\\", "/").rsplit("/", 1)[-1]


print("threads: %d" % len(mf.threads.threads))
shown = 0
for t in mf.threads.threads:
    ctx = t.ContextObject
    rip = getattr(ctx, "Rip", None)
    rsp = getattr(ctx, "Rsp", None)
    m, off = mod_for(rip) if rip else (None, None)
    loc = "%s+%#x" % (name_of(m), off) if m else ("%#x" % rip if rip else "?")
    print("\n=== tid %s  rip=%s  rsp=%#x ===" % (t.ThreadId, loc, rsp or 0))

    # stack scan: return addresses pointing into modules
    chain = []
    if t.Stack:
        for seg in t.Stack.Memory:
            data = getattr(seg, "data", None)
            if not data:
                continue
            base = seg.start_virtual_address
            for i in range(0, len(data) - 8, 8):
                v = struct.unpack_from("<Q", data, i)[0]
                mm, oo = mod_for(v)
                if mm:
                    chain.append((base + i, v, name_of(mm), oo))
    seen = {}
    out = []
    for addr, v, nm, oo in chain:
        key = (nm, oo >> 8)
        if key in seen:
            continue
        seen[key] = True
        out.append("%s+%#x" % (nm, oo))
        if len(out) >= per_thread:
            break
    print("  likely chain: " + " <- ".join(out) if out else "  (no module addresses on stack)")
    shown += 1
    if shown >= max_threads:
        break
