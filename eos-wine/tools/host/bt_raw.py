#!/usr/bin/env python3
"""Reconstruct plausible call chains from raw per-thread stack dumps.

usage: bt_raw.py <maps.txt> <gdb_raw.txt> [only_wine_tids...]
"""
import os, re, subprocess, sys, collections

maps_path, gdb_path = sys.argv[1], sys.argv[2]
want = set(a.lower().lstrip("0x") for a in sys.argv[3:])

maps = []
for line in open(maps_path):
    p = line.split()
    try:
        s, e = [int(x, 16) for x in p[0].split("-")]
    except Exception:
        continue
    off = int(p[2], 16)
    path = " ".join(p[5:]) if len(p) > 5 else ""
    maps.append((s, e, p[1], off, path))
maps.sort()

def mod_of(a):
    for s, e, perm, off, path in maps:
        if s <= a < e:
            base = s - off
            return (path, base, a - base, perm)
    return (None, 0, 0, "")

execmods = {}
for s, e, perm, off, path in maps:
    if "x" in perm and path.startswith("/"):
        execmods.setdefault(path, s - off)

_exports = {}
def exports(path):
    if path in _exports:
        return _exports[path]
    out = []
    try:
        import pefile
        pe = pefile.PE(path, fast_load=True)
        pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT']])
        if hasattr(pe, "DIRECTORY_ENTRY_EXPORT"):
            for sym in pe.DIRECTORY_ENTRY_EXPORT.symbols:
                if sym.name:
                    out.append((sym.address, sym.name.decode(errors="replace")))
    except Exception:
        out = []
    out.sort()
    _exports[path] = out
    return out

_elfcache = {}
def elf_names(path, addrs):
    """addr2line (batch) for ELF module addresses (rva)."""
    if not addrs:
        return {}
    res = subprocess.run(["addr2line", "-f", "-C", "-e", path] + ["0x%x" % a for a in addrs],
                         capture_output=True, text=True).stdout.splitlines()
    d = {}
    for i, a in enumerate(addrs):
        try:
            d[a] = res[2 * i].strip()
        except Exception:
            d[a] = "?"
    return d

def describe(path, rva):
    if not path:
        return "(no module)"
    if path.lower().endswith(".dll") or path.lower().endswith(".exe"):
        ex = exports(path)
        name = "?"
        if ex:
            import bisect
            i = bisect.bisect_right([a for a, _ in ex], rva) - 1
            if i >= 0:
                name = ex[i][1]
        return "%s+0x%x (%s)" % (os.path.basename(path), rva, name)
    names = elf_names(path, [rva])
    return "%s+0x%x (%s)" % (os.path.basename(path), rva, names.get(rva, "?"))

# parse gdb output
threads = collections.OrderedDict()
cur = None
mode = None
for line in open(gdb_path, errors="replace"):
    m = re.match(r'^Thread (\d+) \(LWP (\d+) "([^"]*)"\)', line)
    if m:
        cur = m.group(2)
        threads[cur] = {"name": m.group(3), "tid": None, "rsp": None, "words": []}
        mode = None
        continue
    if cur is None:
        continue
    m = re.match(r'^\$?\d* = (0x[0-9a-f]+)', line.strip())
    if m and "gs_base" in gdb_path:
        pass
    if line.strip().startswith("0x") and ":" in line:
        for w in re.findall(r'0x([0-9a-f]{8,16})', line.split(":", 1)[1]):
            v = int(w, 16)
            threads[cur]["words"].append(v)

# The `p/x` outputs: collect sequentially per thread
tids = {}
rsps = {}
cur = None
for line in open(gdb_path, errors="replace"):
    m = re.match(r'^Thread (\d+) \(LWP (\d+) "([^"]*)"\)', line)
    if m:
        cur = m.group(2)
        continue
    m = re.match(r'^\$?\d* = (0x[0-9a-f]+)\s*$', line.strip())
    if m and cur:
        v = m.group(1)
        if cur not in tids:
            tids[cur] = v
        elif cur not in rsps:
            rsps[cur] = v

for lwp, d in threads.items():
    d["tid"] = tids.get(lwp)
    d["rsp"] = rsps.get(lwp)

print("=== LWP -> wine tid ===")
tid2lwp = {}
for lwp, d in threads.items():
    if d["tid"]:
        tid2lwp[d["tid"]] = lwp
        print("lwp %-8s tid %-6s %s" % (lwp, d["tid"], d["name"]))

for lwp, d in threads.items():
    if want and (d["tid"] or "").lstrip("0x") not in want:
        continue
    print("\n=== LWP %s tid %s %s (rsp=%s) ===" % (lwp, d["tid"], d["name"], d["rsp"]))
    seen = set()
    for v in d["words"]:
        path, base, rva, perm = mod_of(v)
        if path and "x" in perm and path.startswith("/"):
            key = (path, rva)
            if key in seen:
                continue
            seen.add(key)
            print("   %016x  %s" % (v, describe(path, rva)))
