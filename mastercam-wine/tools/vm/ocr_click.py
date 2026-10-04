#!/usr/bin/env python3
"""Find text on the guest console by OCR and click it.

Takes a screenshot, runs tesseract in TSV mode, finds words matching a regex, and clicks the centre
of the best match with tools/vm/vmclick.py (absolute pointer over QMP).

usage: ocr_click.py <regex> [--region x,y,w,h] [--index N] [--dry] [--scale S] [--psm N] [--no-click]
             --type TEXT        type TEXT (tools/vm/vmtype2.py) instead of clicking
             --key KEY[,KEY..]  send virsh send-key codes instead of clicking
Prints the match(es) and what it did.
"""
import argparse
import re
import subprocess
import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DOMAIN = os.environ.get("VM_DOMAIN", "win11")
SHOT = "/tmp/ocr_click.png"


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def screenshot(region=None, scale=1):
    ppm = "/tmp/ocr_click.ppm"
    r = run(["virsh", "screenshot", DOMAIN, ppm])
    if r.returncode != 0:
        sys.exit("screenshot failed: " + r.stderr)
    args = ["convert", ppm]
    if region:
        x, y, w, h = region
        args += ["-crop", f"{w}x{h}+{x}+{y}", "+repage"]
    if scale and scale != 1:
        args += ["-resize", f"{int(scale*100)}%"]
    args += [SHOT]
    r = run(args)
    if r.returncode != 0:
        sys.exit("convert failed: " + r.stderr)
    return SHOT


def ocr_tsv(img, psm=6):
    r = run(["tesseract", img, "stdout", "--psm", str(psm), "tsv"])
    words = []
    for line in r.stdout.splitlines()[1:]:
        f = line.split("\t")
        if len(f) < 12:
            continue
        try:
            left, top, w, h, conf = int(f[6]), int(f[7]), int(f[8]), int(f[9]), float(f[10])
        except ValueError:
            continue
        text = f[11].strip()
        if text and conf > 30:
            words.append((text, left, top, w, h, conf))
    return words


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("regex", nargs="?", default="")
    ap.add_argument("--region", help="x,y,w,h in guest screen coords")
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--psm", type=int, default=6)
    ap.add_argument("--index", type=int, default=0)
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--type", dest="typ")
    ap.add_argument("--key")
    ap.add_argument("--screen", default="1280x800")
    a = ap.parse_args()

    region = tuple(int(v) for v in a.region.split(",")) if a.region else None
    img = screenshot(region, a.scale)
    words = ocr_tsv(img, a.psm)
    if a.list or not (a.regex or a.typ or a.key):
        for w in words:
            print(w)
        return
    if a.regex:
        pat = re.compile(a.regex, re.I)
        hits = [w for w in words if pat.search(w[0])]
        print(f"matches for {a.regex!r}: {[(h[0], h[1], h[2]) for h in hits]}")
        if not hits:
            print("no match; all words:", [w[0] for w in words][:60])
            sys.exit(2)
        if a.index >= len(hits):
            sys.exit("index out of range")
        t, l, tp, w, h, c = hits[a.index]
        scale = a.scale or 1.0
        gx = int((l + w / 2) / scale) + (region[0] if region else 0)
        gy = int((tp + h / 2) / scale) + (region[1] if region else 0)
        print(f"target {t!r} at guest ({gx},{gy})")
        if not a.dry:
            r = run(["python3", os.path.join(HERE, "vmclick.py"), str(gx), str(gy), "--screen", a.screen])
            print(r.stdout.strip() or r.stderr.strip())
    if a.typ:
        r = run(["python3", os.path.join(HERE, "vmtype2.py"), a.typ, "--enter"])
        print(r.stdout.strip() or r.stderr.strip())
    if a.key:
        codes = []
        for k in a.key.split(","):
            codes.append(k if k.startswith("KEY_") else "KEY_" + k.upper())
        r = run(["virsh", "send-key", DOMAIN, "--holdtime", "60"] + codes)
        print("sent keys", codes, r.returncode)


if __name__ == "__main__":
    main()
