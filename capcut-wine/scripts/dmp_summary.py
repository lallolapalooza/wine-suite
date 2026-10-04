#!/usr/bin/env python3
"""Summarise a Windows minidump: exceptions, faulting thread, module map, stack scan.

Usage: dmp_summary.py <dump> [--limit N]

Handles crashpad dumps that carry more than one exception record (the library
exposes those as an ExceptionList, which the older single-exception code crashed on).
Prints, for each exception, the containing module, then scans the faulting thread's
stack for return addresses into modules -- i.e. the call chain that was live when the
process died.
"""
import sys

from minidump.minidumpfile import MinidumpFile

path = sys.argv[1]
limit = 25
if "--limit" in sys.argv:
    limit = int(sys.argv[sys.argv.index("--limit") + 1])

mf = MinidumpFile.parse(path)
print("=== sysinfo ===")
print(mf.sysinfo)

mods = mf.modules.modules if mf.modules else []
print("=== modules (%d) ===" % len(mods))


def mod_for(addr):
    for m in mods:
        if m.baseaddress <= addr < m.baseaddress + (m.size or 0):
            return m, addr - m.baseaddress
    return None, None


def short(name):
    return name.replace("\\", "/").rsplit("/", 1)[-1]


for m in sorted(mods, key=lambda m: m.baseaddress):
    print("  %016x-%016x %s" % (m.baseaddress, m.baseaddress + (m.size or 0), short(m.name)))

# ---- exceptions ------------------------------------------------------------
ex_list = getattr(mf, "exception", None)
recs = []
if ex_list is not None:
    inner = getattr(ex_list, "exceptions", None)
    recs = list(inner) if inner is not None else [ex_list]
    if not recs:
        recs = [ex_list]
print("=== exception records (%d) ===" % len(recs))
fault_tid = None
first_ex = None
for i, e in enumerate(recs):
    code = getattr(e, "ExceptionCode", None)
    addr = getattr(e, "ExceptionAddress", None)
    m, off = mod_for(addr or 0)
    print("[%d] thread=%s code=%s addr=%s flags=%s params=%s" % (
        i, getattr(e, "ThreadId", None),
        hex(code) if code is not None else None,
        hex(addr) if addr else None,
        getattr(e, "ExceptionFlags", None),
        [hex(x) for x in (getattr(e, "ExceptionInformation", None) or [])]))
    try:
        print("    scope: %s" % getattr(e, "scope", None))
    except Exception:
        pass
    print("    module: %s" % ((short(m.name), hex(off)) if m else "unknown"))
    if i == 0:
        fault_tid = getattr(e, "ThreadId", None)
        first_ex = e

# ---- memory map ------------------------------------------------------------
segs = list(getattr(getattr(mf, "memory_segments", None), "memory_segments", None) or [])
try:
    total = sum(len(s.data or b"") for s in segs) / 1e6
except Exception as e:                                   # lazily loaded segments
    total = -1.0
    print("(segment data not resident: %s)" % e)
print("=== memory segments: %d (total %.1f MB dumped) ===" % (len(segs), total))


def seg_for(addr):
    for s in segs:
        if s.start_virtual_address <= addr < s.start_virtual_address + (s.size or 0):
            return s
    return None


# ---- faulting thread stack scan -------------------------------------------
print("=== faulting thread ===")
for t in (mf.threads.threads if mf.threads else []):
    if fault_tid is not None and t.ThreadId != fault_tid:
        continue
    ctx = t.ContextObject
    rip = getattr(ctx, "Rip", None)
    rsp = getattr(ctx, "Rsp", None)
    rbp = getattr(ctx, "Rbp", None)
    print("tid=%s rip=%s rsp=%s rbp=%s" % (t.ThreadId, hex(rip) if rip else None,
                                           hex(rsp) if rsp else None, hex(rbp) if rbp else None))
    if rip:
        m, off = mod_for(rip)
        print("  rip module: %s" % ((short(m.name), hex(off)) if m else "unknown"))
    if not rsp:
        continue
    s = seg_for(rsp)
    if not s or not s.data:
        print("  no stack bytes for rsp")
        continue
    base = s.start_virtual_address
    off = rsp - base
    buf = s.data[off:off + 16384]
    print("  scanning %d bytes of stack from rsp" % len(buf))
    for i in range(0, len(buf) - 7, 8):
        val = int.from_bytes(buf[i:i + 8], "little")
        m, o = mod_for(val)
        if m:
            print("    rsp+%4d  %016x  %s+0x%x" % (i, val, short(m.name), o))
