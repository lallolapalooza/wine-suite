#!/usr/bin/env python3
"""Quantify "the viewport flickers black": sample the display and count how often a region is
near-black.

usage: flicker.py <tag> [--display :2] [--secs 30] [--interval 0.25] [--region x,y,w,h]
                   [--window ID|title] [--outdir DIR]

Writes <outdir>/frame_<n>.png for every frame plus a summary.  Without --region the whole
window/display is used, and both the *whole* area and the *centre rectangle* (where a viewport's
content is) are reported.

Verdict per frame: BLACK (mean < 12 and >98% of pixels below 24), DARK, or CONTENT.  The flicker
signal is `black_fraction` = BLACK frames / frames.
"""
import argparse
import os
import subprocess
import sys
import time

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow")


def grab(display, window, out):
    cmd = ["import", "-display", display]
    if window:
        cmd += ["-window", window]
    else:
        cmd += ["-window", "root"]
    cmd.append(out)
    subprocess.run(cmd, check=True, capture_output=True)


def stats(im, region=None):
    if region:
        im = im.crop(region)
    g = im.convert("L")
    # histogram-based: 1.6M pixels per frame, so avoid per-pixel Python loops
    hist = g.histogram()
    n = sum(hist)
    mean = sum(v * c for v, c in enumerate(hist)) / n
    dark = sum(hist[:24]) / n
    if mean < 12 and dark > 0.98:
        verdict = "BLACK"
    elif mean < 40:
        verdict = "DARK"
    else:
        verdict = "CONTENT"
    return verdict, mean, dark


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("--display", default=os.environ.get("DISP", ":2"))
    ap.add_argument("--secs", type=float, default=30)
    ap.add_argument("--interval", type=float, default=0.25)
    ap.add_argument("--region", default=None, help="x,y,w,h")
    ap.add_argument("--window", default=None, help="X window id (0x...) or exact title")
    ap.add_argument("--outdir", default=None)
    a = ap.parse_args()

    outdir = a.outdir or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                      "logs", "runs", a.tag, "flicker")
    os.makedirs(outdir, exist_ok=True)
    region = None
    if a.region:
        region = tuple(int(v) for v in a.region.split(","))
        region = (region[0], region[1], region[0] + region[2], region[1] + region[3])

    window = a.window
    if window and not window.startswith("0x"):
        tree = subprocess.run(["xwininfo", "-display", a.display, "-root", "-tree"],
                              capture_output=True, text=True).stdout
        for line in tree.splitlines():
            if window in line:
                window = line.strip().split()[0]
                break
        else:
            sys.exit("window %r not found" % a.window)

    frames = int(a.secs / a.interval)
    counts = {"BLACK": 0, "DARK": 0, "CONTENT": 0}
    rows = []
    for i in range(frames):
        t0 = time.time()
        p = os.path.join(outdir, "frame_%04d.png" % i)
        try:
            grab(a.display, window, p)
            im = Image.open(p)
        except Exception as e:                       # window may vanish mid-run
            rows.append((i, "MISSING", 0.0, 0.0, str(e)))
            time.sleep(a.interval)
            continue
        v, mean, dark = stats(im, region)
        counts[v] += 1
        rows.append((i, v, mean, dark, "%dx%d" % im.size))
        if v == "CONTENT":
            os.remove(p)                             # keep the evidence small: only failures
        dt = a.interval - (time.time() - t0)
        if dt > 0:
            time.sleep(dt)

    total = sum(counts.values())
    print("tag=%s display=%s window=%s region=%s frames=%d" %
          (a.tag, a.display, window or "root", region or "all", total))
    for k in ("BLACK", "DARK", "CONTENT"):
        print("  %-8s %4d  %5.1f%%" % (k, counts[k], 100.0 * counts[k] / max(total, 1)))
    print("  black_fraction = %.3f" % (counts["BLACK"] / max(total, 1)))
    if rows:
        print("  first frames:", " ".join(r[1] for r in rows[:12]))
    with open(os.path.join(outdir, "summary.txt"), "w") as f:
        f.write("tag=%s window=%s region=%s\n" % (a.tag, window, region))
        for r in rows:
            f.write("%d\t%s\t%.2f\t%.4f\t%s\n" % r)
    return 0 if counts["BLACK"] == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
