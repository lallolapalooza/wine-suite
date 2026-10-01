#!/usr/bin/env python3
"""Resolve MSI File keys in installer/cabs_x/ to their real names, and hard-link a copy out.

usage: cabx.py ls [regex]           list "<realkey>  <Name>  <size>"
       cabx.py get <Name> [outdir]  link the file(s) whose real name is <Name>
"""
import os, re, sys, collections, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CABS = os.path.join(ROOT, "installer", "cabs_x")
TABLE = os.path.join(ROOT, "state", "msi_File.tsv")


def load():
    rows = [l.rstrip("\n").split("\t") for l in open(TABLE)][4:]
    out = []
    for r in rows:
        if len(r) < 8:
            continue
        key, comp, fname, size = r[0], r[1], r[2].split("|")[-1], r[3]
        p = os.path.join(CABS, key)
        if os.path.exists(p):
            out.append((key, fname, int(size or 0), p))
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "ls"
    entries = load()
    if cmd == "ls":
        pat = sys.argv[2] if len(sys.argv) > 2 else "."
        rx = re.compile(pat, re.I)
        for key, name, size, p in sorted(entries, key=lambda e: e[1].lower()):
            if rx.search(name):
                print(f"{name}\t{size}\t{key}")
    elif cmd == "get":
        name = sys.argv[2].lower()
        outdir = sys.argv[3] if len(sys.argv) > 3 else os.path.join(ROOT, "state", "media_bin")
        os.makedirs(outdir, exist_ok=True)
        n = 0
        for key, fname, size, p in entries:
            if fname.lower() == name:
                dst = os.path.join(outdir, fname)
                if not os.path.exists(dst):
                    try:
                        os.link(p, dst)
                    except OSError:
                        shutil.copy2(p, dst)
                print(os.path.join(outdir, fname))
                n += 1
        if not n:
            sys.exit(f"no cab entry named {name}")
    else:
        sys.exit(__doc__)


main()
