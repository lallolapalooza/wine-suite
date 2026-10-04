#!/usr/bin/env python3
"""Drive winedbg (launch mode) to dump every thread of Eos.exe after the stall.

usage: winedbg_dump.py <outdir> <exe-path> [--settle SECONDS]
"""
import os, re, signal, sys, time, pexpect

outdir = sys.argv[1]
exe = sys.argv[2]
settle = 45
if "--settle" in sys.argv:
    settle = int(sys.argv[sys.argv.index("--settle") + 1])

os.makedirs(outdir, exist_ok=True)
path = os.path.join(outdir, "winedbg.txt")
log = open(path, "wb")

root = os.environ.get("EW", "/home/asdf/projects/eos-wine")
wine = os.environ.get("WINEPREFIX_INSTALL", root + "/wine-install") + "/bin/winedbg"
env = dict(os.environ)
env["PATH"] = os.path.dirname(wine) + ":" + env.get("PATH", "")

child = pexpect.spawn(wine, [exe], env=env, timeout=120, encoding=None,
                      cwd=os.path.dirname(exe), dimensions=(200, 500))
child.logfile_read = log
PROMPT = rb"Wine-dbg>"

def wait_prompt(t=120):
    try:
        child.expect(PROMPT, timeout=t)
        return True
    except pexpect.TIMEOUT:
        log.write(b"\n*** prompt timeout ***\n"); log.flush()
        return False

wait_prompt()
log.write(b"\n===== cont =====\n"); log.flush()
child.sendline(b"cont")
time.sleep(settle)

# try the console Ctrl-C path, then a raw SIGINT, then the pty ^C byte
log.write(b"\n===== interrupt =====\n"); log.flush()
child.kill(signal.SIGINT)
if not wait_prompt(25):
    try:
        child.sendcontrol("c")
    except Exception:
        pass
    if not wait_prompt(25):
        child.send(b"\x03")
        wait_prompt(25)

log.write(b"\n===== info threads =====\n"); log.flush()
child.sendline(b"info threads")
wait_prompt(60)

data = open(path, "rb").read().decode("utf-8", "replace")
tids = re.findall(r"^tid=([0-9a-fA-F]+)", data, re.M)
if not tids:
    tids = re.findall(r"tid=([0-9a-fA-F]+)", data)
tids = list(dict.fromkeys(tids))
log.write(("\nTIDS=%r\n" % tids).encode()); log.flush()

for t in tids:
    log.write(("\n===== thread %s =====\n" % t).encode()); log.flush()
    child.sendline(("thread %s" % t).encode()); wait_prompt(60)
    child.sendline(b"bt"); wait_prompt(60)

log.write(b"\n===== done =====\n"); log.flush()
try:
    child.sendline(b"quit"); time.sleep(2)
except Exception:
    pass
child.close(force=True)
log.close()
print("wrote", path)
