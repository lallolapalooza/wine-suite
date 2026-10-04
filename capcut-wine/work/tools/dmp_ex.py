#!/usr/bin/env python3
"""Robust minidump exception + thread/stack reader for crashpad dumps.

usage: dmp_ex.py <dump> [--mods] [--threads N] [--chain]
"""
import sys
import struct

from minidump.minidumpfile import MinidumpFile

path = sys.argv[1]
show_mods = "--mods" in sys.argv
nthreads = 6
if "--threads" in sys.argv:
    nthreads = int(sys.argv[sys.argv.index("--threads") + 1])

mf = MinidumpFile.parse(path)
mods = sorted(mf.modules.modules, key=lambda m: m.baseaddress) if mf.modules else []


def short(name):
    return (name or "?").replace("\\", "/").rsplit("/", 1)[-1]


def mod_for(addr):
    for m in mods:
        if m.baseaddress <= addr < m.baseaddress + (m.size or 0):
            return m, addr - m.baseaddress
    return None, None


if show_mods:
    print("=== modules (%d) ===" % len(mods))
    for m in mods:
        print("  %016x-%016x %s" % (m.baseaddress, m.baseaddress + (m.size or 0), short(m.name)))

# exception
ex = mf.exception
print("=== exception stream ===")
if ex is None:
    print("  none")
else:
    for attr in ("ThreadId", "ExceptionCode", "ExceptionFlags", "ExceptionAddress",
                 "ExceptionInformation", "NumberParameters", "exception_code",
                 "exception_address", "thread_id"):
        if hasattr(ex, attr):
            v = getattr(ex, attr)
            print("  %s = %s" % (attr, v))
    if hasattr(ex, "__dict__"):
        for k, v in ex.__dict__.items():
            print("  raw %s = %r" % (k, v))
    tt = getattr(ex, "ThreadId", None)
    if tt is None:
        tt = getattr(ex, "thread_id", None)
    ea = getattr(ex, "ExceptionAddress", None)
    if ea is None:
        ea = getattr(ex, "exception_address", None)
    if ea:
        m, off = mod_for(ea)
        print("  addr module: %s" % ("%s+0x%x" % (short(m.name), off) if m else "unknown"))
    if tt is not None:
        print("  faulting tid = %#x" % tt)

# threads
print("=== threads (%d) ===" % len(mf.threads.threads))
mems = list(getattr(mf, "memory_segments", None).memory_segments) if getattr(mf, "memory_segments", None) else []


def stack_bytes(t):
    # walk the thread stack memory descriptor / segments
    out = []
    segs = []
    st = getattr(t, "Stack", None)
    if st is not None:
        for attr in ("Memory", "memory"):
            v = getattr(st, attr, None)
            if v:
                segs = list(v)
                break
    if not segs:
        rsp = getattr(t.ContextObject, "Rsp", None)
        if rsp:
            for s in mems:
                if s.start_virtual_address <= rsp < s.start_virtual_address + s.size:
                    segs = [s]
                    break
    for s in segs:
        data = getattr(s, "data", None)
        if data is None and hasattr(s, "read"):
            try:
                data = s.read()
            except Exception:
                data = None
        if data:
            out.append((s.start_virtual_address, data))
    return out


for i, t in enumerate(mf.threads.threads):
    ctx = t.ContextObject
    rip = getattr(ctx, "Rip", None)
    m, off = mod_for(rip) if rip else (None, None)
    loc = "%s+0x%x" % (short(m.name), off) if m else (hex(rip) if rip else "?")
    print("  tid %#-6x rip=%s" % (t.ThreadId, loc))
    if i + 1 >= nthreads:
        break
