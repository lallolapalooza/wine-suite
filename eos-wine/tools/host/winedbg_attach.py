#!/usr/bin/env python3
"""Attach winedbg to a running Wine process (by *Wine* pid) and dump every thread.

usage: winedbg_attach.py <outfile> <winepid-hex> [settle]
"""
import os, re, sys, time, pexpect

outfile = sys.argv[1]
wpid = sys.argv[2]
root = os.environ.get("EW", "/home/asdf/projects/eos-wine")
wine = os.environ.get("WINEPREFIX_INSTALL", root + "/wine-install") + "/bin/winedbg"
env = dict(os.environ)
env["PATH"] = os.path.dirname(wine) + ":" + env.get("PATH", "")

log = open(outfile, "wb")
c = pexpect.spawn(wine, [wpid], env=env, timeout=180, encoding=None, dimensions=(200, 500))
c.logfile_read = log
PROMPT = rb"Wine-dbg>"

def wait(t=180):
    try:
        c.expect(PROMPT, timeout=t); return True
    except pexpect.TIMEOUT:
        log.write(b"\n*** prompt timeout ***\n"); log.flush(); return False

wait()
log.write(b"\n===== info threads =====\n"); log.flush()
c.sendline(b"info threads"); wait()
log.flush()
time.sleep(0.3)
data = open(outfile, "rb").read().decode("utf-8", "replace")
tids = list(dict.fromkeys(re.findall(r"tid=([0-9a-fA-F]+)", data)))
log.write(("\nTIDS=%r\n" % tids).encode()); log.flush()
for t in tids:
    log.write(("\n===== thread %s =====\n" % t).encode()); log.flush()
    c.sendline(("thread %s" % t).encode()); wait()
    c.sendline(b"bt"); wait()
log.write(b"\n===== done =====\n"); log.flush()
try:
    c.sendline(b"detach"); wait(60)
except Exception:
    pass
c.close(force=True)
log.close()
print("wrote", outfile)
