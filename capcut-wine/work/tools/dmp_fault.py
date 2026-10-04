#!/usr/bin/env python3
"""Disassemble the faulting instruction straight out of a crashpad minidump.

The unpacked VMProtect code lives in the dumped module image, so the fault address
can be read back and disassembled even though the on-disk .text is empty.

usage: dmp_fault.py <dump> [--bytes N] [--out DIR]
"""
import os
import subprocess
import sys

from minidump.minidumpfile import MinidumpFile

path = sys.argv[1]
nbytes = 256
outdir = "/tmp/fault"
if "--bytes" in sys.argv:
    nbytes = int(sys.argv[sys.argv.index("--bytes") + 1])
if "--out" in sys.argv:
    outdir = sys.argv[sys.argv.index("--out") + 1]
os.makedirs(outdir, exist_ok=True)

mf = MinidumpFile.parse(path)
reader = mf.get_reader()
mods = sorted(mf.modules.modules, key=lambda m: m.baseaddress)


def short(name):
    return (name or "?").replace("\\", "/").rsplit("/", 1)[-1]


def mod_for(addr):
    for m in mods:
        if m.baseaddress <= addr < m.baseaddress + (m.size or 0):
            return m, addr - m.baseaddress
    return None, None


ex = mf.exception.exception_records[0]
er = ex.ExceptionRecord
addr = er.ExceptionAddress
tid = ex.ThreadId
m, off = mod_for(addr)
print("exception code %#x addr %#x  -> %s+%#x  tid %#x" %
      (er.ExceptionCode_raw, addr, short(m.name) if m else "?", off or 0, tid))
print("information %r" % (er.ExceptionInformation,))

# registers of the faulting thread
print("=== faulting thread registers ===")
for t in mf.threads.threads:
    if t.ThreadId != tid:
        continue
    ctx = t.ContextObject
    for r in ("Rax", "Rbx", "Rcx", "Rdx", "Rsi", "Rdi", "Rbp", "Rsp", "R8", "R9",
              "R10", "R11", "R12", "R13", "R14", "R15", "Rip", "EFlags"):
        if hasattr(ctx, r):
            print("  %-4s = %#018x" % (r, getattr(ctx, r)))
    # stack words
    rsp = ctx.Rsp
    print("  --- stack at rsp ---")
    for i in range(0, 24):
        try:
            v = int.from_bytes(reader.read(rsp + i * 8, 8), "little")
        except Exception as e:
            print("   rsp+%3d  <unreadable: %s>" % (i * 8, e))
            break
        mm, oo = mod_for(v)
        print("   rsp+%3d  %#018x  %s" % (i * 8, v, ("%s+%#x" % (short(mm.name), oo)) if mm else ""))

# bytes around the fault
start = addr - nbytes
data = reader.read(start, nbytes * 2)
raw = os.path.join(outdir, "fault.bin")
with open(raw, "wb") as f:
    f.write(data)
print("=== %d bytes at %#x written to %s ===" % (len(data), start, raw))
dis = subprocess.run(["objdump", "-D", "-b", "binary", "-m", "i386:x86-64",
                      "--adjust-vma=%#x" % start, raw],
                     capture_output=True, text=True)
lines = dis.stdout.splitlines()
for ln in lines:
    print(ln)
