#!/usr/bin/env python3
"""Find, in a PE, where an imported function is called.

usage: xref.py <pe> <import-name> [<import-name> ...]

Handles both call shapes MSVC/clang emit for imports into a PE without import thunks:
`call qword ptr [rip+disp]` (FF 15) and the `jmp qword ptr [rip+disp]` (FF 25) thunk, whose
address is then reached with E8 relative calls.  Prints the absolute VAs of the call sites.
"""
import re
import struct
import subprocess
import sys


def load(pe):
    p = subprocess.run(["objdump", "-p", pe], capture_output=True, text=True).stdout
    ib = int(re.search(r"ImageBase\s+([0-9a-fA-F]+)", p).group(1), 16)
    h = subprocess.run(["objdump", "-h", pe], capture_output=True, text=True).stdout
    secs = []
    for line in h.splitlines():
        m = re.match(r"\s*\d+\s+(\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)", line)
        if m:
            secs.append((m.group(1), int(m.group(2), 16), int(m.group(3), 16), int(m.group(5), 16)))
    return p, ib, secs, open(pe, "rb").read()


def main():
    pe = sys.argv[1]
    names = sys.argv[2:]
    p, ib, secs, data = load(pe)
    text = [s for s in secs if s[0] == ".text"][0]
    _, ts, tv, to = text
    t = data[to:to + ts]

    def ind(op):
        res = []
        for k in range(len(t) - 6):
            if t[k] == 0xFF and t[k + 1] == op:
                res.append((tv + k, tv + k + 6 + struct.unpack_from("<i", t, k + 2)[0]))
        return res

    calls, jmps = ind(0x15), ind(0x25)
    print(f"# {pe} imagebase {ib:#x} text {ts} bytes")
    for name in names:
        m = re.search(r"^\s+([0-9a-f]+)\s+<none>\s+\S+\s+" + re.escape(name) + r"$", p, re.M)
        if not m:
            print(f"{name}: not imported")
            continue
        # the import listing prints RVAs
        iat = ib + int(m.group(1), 16)
        direct = [a for a, tgt in calls if tgt == iat]
        thunks = [a for a, tgt in jmps if tgt == iat]
        print(f"\n{name}: IAT {iat:#x}")
        for a in direct:
            print(f"  call  {a:#x}")
        for th in thunks:
            print(f"  thunk {th:#x}")
            for k in range(len(t) - 5):
                if t[k] == 0xE8 and tv + k + 5 + struct.unpack_from("<i", t, k + 1)[0] == th:
                    print(f"    called from {tv + k:#x}")


main()
