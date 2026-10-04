#!/usr/bin/env python3
"""Load a minidump in winedbg and dump every thread's backtrace.

usage: mdump_bt.py <outfile> <file.dmp>
"""
import os, re, subprocess, sys, time, pexpect

outfile, dmp = sys.argv[1], sys.argv[2]
root = os.environ.get("EW", "/home/asdf/projects/eos-wine")
wine = os.environ.get("WINEPREFIX_INSTALL", root + "/wine-install") + "/bin/winedbg"
env = dict(os.environ)
env["PATH"] = os.path.dirname(wine) + ":" + env.get("PATH", "")

def run(cmdlines, timeout=180):
    log = open(outfile + ".tmp", "wb")
    c = pexpect.spawn(wine, [dmp], env=env, timeout=timeout, encoding=None, dimensions=(200, 500))
    c.logfile_read = log
    try:
        c.expect([rb"Wine-dbg>", rb"WineDbg>"], timeout=timeout)
    except pexpect.TIMEOUT:
        log.write(b"\n*** no prompt ***\n")
    for cmd in cmdlines:
        c.sendline(cmd.encode())
        try:
            c.expect([rb"Wine-dbg>", rb"WineDbg>"], timeout=timeout)
        except pexpect.TIMEOUT:
            log.write(("\n*** timeout on %s ***\n" % cmd).encode())
    try:
        c.sendline(b"quit"); time.sleep(1)
    except Exception:
        pass
    c.close(force=True)
    log.close()
    return open(outfile + ".tmp", "rb").read().decode("utf-8", "replace")

txt = run(["info threads"])
open(outfile, "w").write(txt)
tids = re.findall(r"^\s+([0-9a-f]{4,8})\s", txt, re.M)
tids = list(dict.fromkeys(t for t in tids if t not in ("0000",)))
cmds = []
for t in tids:
    cmds += ["thread %s" % t, "bt"]
txt2 = run(cmds, timeout=240)
open(outfile, "w").write(txt + "\n\n########## PER-THREAD BACKTRACES ##########\n" + txt2)
print("threads:", len(tids), "->", outfile)
