#!/usr/bin/env python3
"""gdb -p PID -batch -x this: dump per-thread wine tid, TEB stack bounds and
(optionally) the Windows thread stack bytes for offline walk.

Set DUMPDIR; set STACK_BYTES to cap the dump per thread (default 0x40000).
"""
import os
import gdb

outdir = os.environ.get("DUMPDIR", "/tmp/windump")
os.makedirs(outdir, exist_ok=True)
cap = int(os.environ.get("STACK_BYTES", "0x40000"), 0)

rows = []
for th in gdb.selected_inferior().threads():
    try:
        th.switch()
    except Exception:
        continue
    lwp = th.ptid[1]
    try:
        gs = int(gdb.parse_and_eval("$gs_base")) & 0xFFFFFFFFFFFFFFFF
        rsp = int(gdb.parse_and_eval("$rsp"))
        tid = int(gdb.parse_and_eval("*(unsigned long*)($gs_base+0x48)"))
        sbase = int(gdb.parse_and_eval("*(unsigned long*)($gs_base+0x08)"))
        slim = int(gdb.parse_and_eval("*(unsigned long*)($gs_base+0x10)"))
    except Exception as e:
        rows.append((lwp, 0, 0, 0, 0, 0, "err:%s" % e))
        continue
    note = ""
    good = (0x10000 <= sbase - slim <= 0x2000000 and slim <= rsp <= sbase)
    if not good:
        note = "rsp_outside"
    if sbase and slim and 0x10000 <= sbase - slim <= 0x2000000:
        start = max(slim, sbase - cap)
        try:
            mem = gdb.selected_inferior().read_memory(start, sbase - start)
            fn = os.path.join(outdir, "stk_%08x_%d.bin" % (tid, lwp))
            open(fn, "wb").write(mem.tobytes())
        except Exception as e:
            note += " read_fail:%s" % e
    rows.append((lwp, tid, gs, sbase, slim, rsp, note))

with open(os.path.join(outdir, "threads.txt"), "w") as f:
    f.write("lwp tid gs stackbase stacklimit rsp note\n")
    for r in rows:
        f.write("%d 0x%x 0x%x 0x%x 0x%x 0x%x %s\n" % r)
print("dumped %d threads to %s" % (len(rows), outdir))
