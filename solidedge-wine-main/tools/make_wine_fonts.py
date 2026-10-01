#!/usr/bin/env python3
"""Build the two font families the AutoCAD WPF UI needs but a Wine prefix does not ship.

Why this exists
---------------
AutoCAD's XAML (`AcWindows.dll`) and its command line ask WPF for the families
`Arial` and `Microsoft Sans Serif` by name.  Wine's prefix ships neither as a file,
and WPF's font resolution goes through DirectWrite, which does not consult the GDI
`FontSubstitutes` table - so the families have to exist as real font files in
`C:\\windows\\Fonts`, registered under `HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts`.
Without them WPF throws `ArgumentException: Font 'Microsoft Sans Serif' cannot be found.`
(see FINDINGS MILESTONE 19/22) and acad's UI fails to build.

Windows gets these from its own font collection; we have no Windows fonts here, so we
build metric-compatible substitutes from fonts that are already on the machine:

  Arial                 <- Liberation Sans  (designed to be metric-compatible with Arial)
  Microsoft Sans Serif  <- Wine's tahoma.ttf (the same class of fix the project used before)

usage: make_wine_fonts.py <output-dir>
writes arial.ttf, arialbd.ttf and micross.ttf into <output-dir>.
"""
import os
import sys

from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAHOMA = next((p for p in [os.path.join(ROOT, "wine", "install", "share", "wine", "fonts", "tahoma.ttf"),
                      "/opt/wine-staging/share/wine/fonts/tahoma.ttf",
                      "/usr/share/wine/fonts/tahoma.ttf"] if os.path.exists(p)),
              os.path.join(ROOT, "wine-install", "share", "wine", "fonts", "tahoma.ttf"))
LIBERATION_DIRS = [
    "/usr/share/fonts/truetype/liberation",
    "/usr/share/fonts/liberation",
]

# (output file, source file, family, subfamily, full name, postscript name)
JOBS = [
    ("arial.ttf", "LiberationSans-Regular.ttf", "Arial", "Regular", "Arial", "Arial"),
    ("arialbd.ttf", "LiberationSans-Bold.ttf", "Arial", "Bold", "Arial Bold", "Arial-Bold"),
    ("micross.ttf", TAHOMA, "Microsoft Sans Serif", "Regular", "Microsoft Sans Serif",
     "MicrosoftSansSerif"),
]


def find_source(name):
    if os.path.isabs(name):
        return name if os.path.exists(name) else None
    for d in LIBERATION_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return None


def set_names(font, family, subfamily, full, psname):
    """Rewrite the name table so the family is what WPF asks for."""
    name = font["name"]
    # Drop the existing identity records, then write ours for both Mac and Windows platforms.
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17):
            name.names.remove(rec)
    records = {1: family, 2: subfamily, 3: full, 4: full, 6: psname, 16: family, 17: subfamily}
    for nid, value in records.items():
        # Mac Roman, Windows Unicode BMP (en-US) and Windows Unicode BMP (language neutral).
        name.setName(value, nid, 1, 0, 0)
        name.setName(value, nid, 3, 1, 0x409)
        name.setName(value, nid, 3, 1, 0x0)
    # The typographic names must not point back at the original family.
    for nid in (16, 17):
        if not [r for r in name.names if r.nameID == nid]:
            name.setName(family if nid == 16 else subfamily, nid, 3, 1, 0x409)


def build(out_dir, out_name, src_name, family, subfamily, full, psname):
    src = find_source(src_name)
    if not src:
        return f"SKIP {out_name}: source {src_name} not found"
    font = TTFont(src, recalcBBoxes=False, recalcTimestamp=False)
    set_names(font, family, subfamily, full, psname)
    dst = os.path.join(out_dir, out_name)
    font.save(dst)
    font.close()
    return f"built {out_name} <- {src} ({os.path.getsize(dst)} bytes, family '{family}')"


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    rc = 0
    for job in JOBS:
        msg = build(out_dir, *job)
        print(msg)
        if msg.startswith("SKIP"):
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
