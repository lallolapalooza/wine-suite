#!/usr/bin/env python3
"""Watch the X window tree and report what changes, with timestamps.

A viewport that "flickers black continuously" is often a window being created, destroyed,
reparented, moved or resized on every frame — which this makes visible, and which a black-frame
count alone cannot distinguish from a paint-order problem.

usage: winwatch.py [--display :2] [--secs 30] [--interval 0.2] [--filter regex] [--out FILE]

Each change line is `t=+S.ss  <kind>  <id>  <detail>`; a per-second summary of the churn is
printed at the end, plus how often each window appears and disappears.
"""
import argparse
import collections
import os
import re
import subprocess
import sys
import time


def tree(display):
    out = subprocess.run(["xwininfo", "-display", display, "-root", "-tree"],
                         capture_output=True, text=True).stdout
    wins = {}
    for line in out.splitlines():
        m = re.match(r"\s+(0x[0-9a-f]+)\s+(.*)$", line)
        if not m:
            continue
        wid, rest = m.group(1), m.group(2).strip()
        geo = ""
        g = re.search(r"(\d+x\d+[+-]\d+[+-]\d+)\s+([+-]\d+[+-]\d+)\s*$", rest)
        if g:
            geo = g.group(2)          # absolute geometry
            rest = rest[:g.start()].strip()
        title = rest.split(":")[0].strip().strip('"')
        cls = ""
        c = re.search(r'\(([^)]*)\)\s*$', rest)
        if c:
            cls = c.group(1)
        wins[wid] = (title, cls, geo)
    return wins


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--display", default=os.environ.get("DISP", ":2"))
    ap.add_argument("--secs", type=float, default=30)
    ap.add_argument("--interval", type=float, default=0.2)
    ap.add_argument("--filter", default=None)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    rx = re.compile(a.filter) if a.filter else None
    prev = {}
    created = collections.Counter()
    destroyed = collections.Counter()
    moved = collections.Counter()
    lines = []
    t0 = time.time()
    out = open(a.out, "w") if a.out else None

    def emit(s):
        lines.append(s)
        if out:
            out.write(s + "\n")
            out.flush()

    while time.time() - t0 < a.secs:
        cur = tree(a.display)
        if rx:
            cur = {k: v for k, v in cur.items() if rx.search(v[0] + " " + v[1] + " " + k)}
            prev = {k: v for k, v in prev.items() if k in cur or True}
        now = time.time() - t0
        for wid, v in cur.items():
            if wid not in prev:
                created[v[0] or v[1] or wid] += 1
                emit("t=+%.2f  CREATE  %s  %s/%s  %s" % (now, wid, v[0], v[1], v[2]))
            elif prev[wid][2] != v[2]:
                moved[v[0] or v[1] or wid] += 1
                emit("t=+%.2f  GEOM    %s  %s  %s -> %s" % (now, wid, v[0], prev[wid][2], v[2]))
        for wid, v in prev.items():
            if wid not in cur:
                destroyed[v[0] or v[1] or wid] += 1
                emit("t=+%.2f  DESTROY %s  %s/%s" % (now, wid, v[0], v[1]))
        prev = cur
        time.sleep(a.interval)

    print("observed %d windows over %.1fs" % (len(prev), a.secs))
    if created:
        print("most (re)created windows:")
        for name, c in created.most_common(10):
            print("   %5d  %s" % (c, name))
    if destroyed:
        print("most destroyed windows:")
        for name, c in destroyed.most_common(10):
            print("   %5d  %s" % (c, name))
    if moved:
        print("most geometry changes:")
        for name, c in moved.most_common(10):
            print("   %5d  %s" % (c, name))
    if not (created or destroyed or moved):
        print("the window tree did not change")
    if out:
        out.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
