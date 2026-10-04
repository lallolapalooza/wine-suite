#!/usr/bin/env python3
"""Dismiss known blocking dialogs on a Wine display while an unattended install runs.

Measured need: winetricks' dotnet40/dotnet48 verbs raise modal windows that wait for a click, and
an unattended install then sits there forever.  Observed on `:2` during `tools/install_se_prefix.sh`:

    rundll32.exe - .NET Framework Initialization Error
    "Unable to find a version of the runtime to run this application."   [OK]

usage: dismiss_dialogs.py [--display :2] [--secs 600] [--interval 2] [--dry-run]

The patterns below are the ones seen or known to block; each is clicked on its default button
(Return) after being raised.  Every action is logged with a timestamp.
"""
import argparse
import re
import subprocess
import sys
import time

PATTERNS = [
    r"\.NET Framework Initialization Error",
    r"Microsoft \.NET Framework",
    r"Program Error",
    r"winedbg",
    r"Runtime Error",
    r"Windows Installer",
    r"InstallShield",
    r"Fatal Error",
    r"Assertion Failed",
]

OK_KEYS = ["Return"]


def windows(display):
    out = subprocess.run(["xwininfo", "-display", display, "-root", "-tree"],
                         capture_output=True, text=True).stdout
    res = []
    for line in out.splitlines():
        m = re.match(r'\s+(0x[0-9a-f]+)\s+"(.*?)"', line)
        if m:
            res.append((m.group(1), m.group(2)))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--display", default=":2")
    ap.add_argument("--secs", type=float, default=600)
    ap.add_argument("--interval", type=float, default=2)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    rx = [re.compile(p, re.I) for p in PATTERNS]
    seen = set()
    t0 = time.time()
    print("watching %s for blocking dialogs for %.0fs" % (a.display, a.secs))
    while time.time() - t0 < a.secs:
        for wid, title in windows(a.display):
            if not any(r.search(title) for r in rx):
                continue
            key = (wid, title)
            if key in seen:
                continue
            seen.add(key)
            stamp = time.strftime("%H:%M:%S")
            if a.dry_run:
                print("%s would dismiss %s %r" % (stamp, wid, title))
                continue
            print("%s dismissing %s %r" % (stamp, wid, title))
            subprocess.run(["xdotool", "windowactivate", "--sync", wid],
                           env={"DISPLAY": a.display, "PATH": "/usr/bin:/bin"}, capture_output=True)
            for _ in range(2):
                subprocess.run(["xdotool", "key", "--window", wid, "Return"],
                               env={"DISPLAY": a.display, "PATH": "/usr/bin:/bin"}, capture_output=True)
                time.sleep(0.3)
        if time.time() - t0 > a.secs:
            break
        time.sleep(a.interval)
    print("dismissed %d dialog(s)" % len(seen))
    return 0


if __name__ == "__main__":
    sys.exit(main())
