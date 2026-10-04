#!/usr/bin/env python3
"""Drive the wine app on the Xvfb display: capture, OCR, locate text, click, type.

This model cannot receive images through the read tool (the harness drops them), so all
"seeing" is programmatic: screen capture + tesseract OCR + pixel analysis.

usage:
  uix.py shot [out.png]                 capture the display (default state/shot.png)
  uix.py ocr [img]                      print OCR text of the display / of img
  uix.py find <text> [img]              print "x y text" lines whose OCR text matches
  uix.py click <text> [--nth N]         click the Nth match (1-based) of <text>
  uix.py clickxy <x> <y>                click absolute coordinates
  uix.py key <keysym> [keysym...]       send keys (xdotool syntax, e.g. ctrl+s)
  uix.py type <text>                    type a literal string
  uix.py windows                        list X windows (wmctrl -l)
  uix.py pixel <x> <y>                  print the RGB value at a point
  uix.py diff <a.png> <b.png>           print changed-pixel count and bbox (flicker detector)
"""
import os
import re
import subprocess
import sys

DISP = os.environ.get("DISP", ":20")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SHOT = os.path.join(ROOT, "state", "shot.png")


def run(cmd, **kw):
    env = dict(os.environ, DISPLAY=DISP)
    return subprocess.run(cmd, env=env, capture_output=True, text=True, **kw)


def shot(out=None):
    out = out or DEFAULT_SHOT
    os.makedirs(os.path.dirname(out), exist_ok=True)
    run(["import", "-window", "root", out])
    return out


def ocr_tsv(img):
    """Return [(x, y, w, h, conf, text)] via tesseract TSV."""
    p = run(["tesseract", img, "stdout", "--psm", "11", "tsv"])
    rows = []
    for line in p.stdout.splitlines()[1:]:
        f = line.split("\t")
        if len(f) < 12 or not f[11].strip():
            continue
        try:
            conf = float(f[10])
        except ValueError:
            continue
        if conf < 30:
            continue
        rows.append((int(f[6]), int(f[7]), int(f[8]), int(f[9]), conf, f[11]))
    return rows


def pixel(x, y):
    p = run(["import", "-window", "root", "-crop", f"1x1+{x}+{y}", "-depth", "8", "txt:-"])
    m = re.search(r"#([0-9A-Fa-f]{6})", p.stdout)
    return m.group(1) if m else None


def diff(a, b):
    p = run(["compare", "-metric", "AE", a, b, "null:"])
    out = (p.stderr or "").strip()
    num = re.match(r"(\d+)", out)
    return int(num.group(1)) if num else -1


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    cmd = sys.argv[1]
    if cmd == "shot":
        print(shot(sys.argv[2] if len(sys.argv) > 2 else None))
    elif cmd == "ocr":
        img = sys.argv[2] if len(sys.argv) > 2 else shot()
        for x, y, w, h, c, t in ocr_tsv(img):
            print(f"{x}\t{y}\t{w}\t{h}\t{t}")
    elif cmd == "find":
        needle = sys.argv[2].lower()
        img = sys.argv[3] if len(sys.argv) > 3 else shot()
        for x, y, w, h, c, t in ocr_tsv(img):
            if needle in t.lower():
                print(f"{x + w // 2} {y + h // 2} {t}")
    elif cmd == "click":
        needle = sys.argv[2].lower()
        nth = 1
        if "--nth" in sys.argv:
            nth = int(sys.argv[sys.argv.index("--nth") + 1])
        img = shot()
        hits = [(x, y, w, h, t) for x, y, w, h, c, t in ocr_tsv(img) if needle in t.lower()]
        if len(hits) < nth:
            print(f"no match {nth}/{len(hits)} for {needle!r}")
            return 1
        x, y, w, h, t = hits[nth - 1]
        run(["xdotool", "mousemove", str(x + w // 2), str(y + h // 2), "click", "1"])
        print(f"clicked {x + w // 2},{y + h // 2} on {t!r}")
    elif cmd == "clickxy":
        run(["xdotool", "mousemove", sys.argv[2], sys.argv[3], "click", "1"])
        print(f"clicked {sys.argv[2]},{sys.argv[3]}")
    elif cmd == "key":
        run(["xdotool", "key"] + sys.argv[2:])
        print("sent " + " ".join(sys.argv[2:]))
    elif cmd == "type":
        run(["xdotool", "type", "--delay", "40", sys.argv[2]])
        print("typed")
    elif cmd == "windows":
        print(run(["wmctrl", "-l"]).stdout)
    elif cmd == "pixel":
        print(pixel(int(sys.argv[2]), int(sys.argv[3])))
    elif cmd == "diff":
        print(diff(sys.argv[2], sys.argv[3]))
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
