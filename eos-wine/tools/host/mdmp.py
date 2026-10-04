#!/usr/bin/env python3
"""Parse a Windows minidump (MDMP) directly: per-thread PE context + stack walk.

usage: mdmp.py <dump> [tid-filter...]
"""
import struct, sys, os, bisect

dump = sys.argv[1]
filt = set(int(a, 16) for a in sys.argv[2:])
data = open(dump, "rb").read()

assert data[:4] == b"MDMP", "not a minidump"
(nstreams, dirrva) = struct.unpack_from("<II", data, 8)

streams = {}
for i in range(nstreams):
    stype, size, rva = struct.unpack_from("<III", data, dirrva + i * 12)
    streams.setdefault(stype, []).append((rva, size))

mods = []
for rva, size in streams.get(4, []):
    n = struct.unpack_from("<I", data, rva)[0]
    for i in range(n):
        off = rva + 4 + i * 108
        base, sizeimg = struct.unpack_from("<QI", data, off)
        namerva = struct.unpack_from("<I", data, off + 20)[0]
        ln = struct.unpack_from("<I", data, namerva)[0]
        name = data[namerva + 4:namerva + 4 + ln].decode("utf-16-le", "replace")
        mods.append((base, base + sizeimg, name))
print("# %d modules" % len(mods))

def mod_of(a):
    for b, e, n in mods:
        if b <= a < e:
            return n, a - b
    return None

_exports = {}
def exports(path):
    if path in _exports:
        return _exports[path]
    try:
        import pefile
        pe = pefile.PE(path, fast_load=True)
        pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT']])
        lst = sorted((s.address, s.name.decode("utf8", "replace"))
                     for s in pe.DIRECTORY_ENTRY_EXPORT.symbols if s.name)
    except Exception:
        lst = []
    _exports[path] = lst
    return lst

def modpath(name):
    bn = os.path.basename(name.replace("\\", "/"))
    cands = [os.path.join(os.environ.get("APP_DIR", ""), bn),
             os.path.join(os.environ.get("APP_DIR", ""), bn.lower()),
             os.path.join(os.environ.get("WINEPREFIX_INSTALL", "") + "/lib/wine/x86_64-windows", bn),
             os.path.join(os.environ.get("WINEPREFIX_INSTALL", "") + "/lib/wine/x86_64-windows", bn.lower())]
    for c in cands:
        if c and os.path.exists(c):
            return c
    return None

def sym(name, rva):
    p = modpath(name)
    if not p:
        return ""
    ex = exports(p)
    i = bisect.bisect_right([a for a, _ in ex], rva) - 1
    return ex[i][1] if i >= 0 else ""

# exception stream
for rva, size in streams.get(6, []):
    etid = struct.unpack_from("<I", data, rva)[0]
    code, flags, rec, addr = struct.unpack_from("<IIQQ", data, rva + 8)
    print("# EXCEPTION tid=0x%x code=0x%x flags=0x%x addr=0x%x" % (etid, code, flags, addr))
    m = mod_of(addr)
    if m:
        print("#   addr in %s+0x%x %s" % (m[0], m[1], ""))
    npar = struct.unpack_from("<I", data, rva + 32)[0]
    for i in range(min(npar, 15)):
        par = struct.unpack_from("<Q", data, rva + 36 + i * 8)[0]
        mm = mod_of(par)
        print("#   param[%d]=0x%x %s" % (i, par, ("%s+0x%x" % (mm[0], mm[1])) if mm else ""))

threads = []
for rva, size in streams.get(3, []):
    n = struct.unpack_from("<I", data, rva)[0]
    for i in range(n):
        off = rva + 4 + i * 48
        tid, susp, priocls, prio = struct.unpack_from("<IIII", data, off)
        teb = struct.unpack_from("<Q", data, off + 16)[0]
        stk_start, stk_size, stk_rva = struct.unpack_from("<QII", data, off + 24)
        ctx_size, ctx_rva = struct.unpack_from("<II", data, off + 40)
        ctx = data[ctx_rva:ctx_rva + ctx_size]
        rip = struct.unpack_from("<Q", ctx, 0xF8)[0]
        rsp = struct.unpack_from("<Q", ctx, 0x98)[0]
        rbp = struct.unpack_from("<Q", ctx, 0xA0)[0]
        threads.append(dict(tid=tid, rip=rip, rsp=rsp, rbp=rbp,
                            stk_start=stk_start, stk_size=stk_size, stk_rva=stk_rva))

for t in threads:
    if filt and t["tid"] not in filt:
        continue
    print("\n=== tid 0x%x  rip=%016x rsp=%016x rbp=%016x  stack=[%x+%x] ===" %
          (t["tid"], t["rip"], t["rsp"], t["rbp"], t["stk_start"], t["stk_size"]))
    m = mod_of(t["rip"])
    print("   pc: %s" % (("%s+0x%x %s" % (m[0], m[1], sym(*m))) if m else hex(t["rip"])))
    # walk the stack words
    base = t["stk_start"]
    blob = data[t["stk_rva"]:t["stk_rva"] + t["stk_size"]]
    if not (base <= t["rsp"] < base + len(blob)):
        print("   (rsp outside captured stack)")
        continue
    start = t["rsp"] - base
    seen = 0
    for k in range(start, len(blob) - 8, 8):
        v = struct.unpack_from("<Q", blob, k)[0]
        m = mod_of(v)
        if m:
            addr = base + k
            print("   +0x%04x %016x  %s+0x%x %s" % (k - start, v, m[0], m[1], sym(*m)))
            seen += 1
            if seen > 40:
                break
    if not seen:
        print("   (no module addresses in stack window)")
