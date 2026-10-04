#!/usr/bin/env python3
"""Read or change a key in the prefix's Power BI user state (User.zip → UserInterface/Settings.xml).

The state decides which view a document opens into, so the canvas loop needs to change it repeatably and to put it
back. Values use Power BI's own encoding in the XML: `l0`/`l1` are bools, `s<json>` is a string, `i<n>` an int.

usage:
  pbi_state.sh <prefix> list
  pbi_state.sh <prefix> get  <Key>
  pbi_state.sh <prefix> set  <Key> <l0|l1|sJSON|s"text"|iN>
  pbi_state.sh <prefix> del  <Key>
  pbi_state.sh <prefix> save <file>      # copy the current Settings.xml out (for diffing / restoring)
  pbi_state.sh <prefix> load <file>      # write a Settings.xml back in

Always stop the app first (wineserver -k) — the app rewrites User.zip when it exits, which would silently undo you.
"""
import re, shutil, sys, zipfile, os

MEMBER = "UserInterface/Settings.xml"


def prefix_state(prefix):
    return os.path.join(prefix, "drive_c/users/asdf/AppData/Local/Microsoft/Power BI Desktop/User.zip")


def read(zp):
    with zipfile.ZipFile(zp) as z:
        return z.read(MEMBER).decode("utf-8-sig")


def write(zp, text):
    """Rewrite the single member in place, preserving everything else in the archive."""
    tmp = zp + ".new"
    with zipfile.ZipFile(zp) as z:
        others = [(i, z.read(i.filename)) for i in z.infolist() if i.filename != MEMBER]
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(MEMBER, text)
        for info, data in others:
            z.writestr(info, data)
    os.replace(tmp, zp)


def entries(text):
    return re.findall(r'<Entry Type="([^"]+)" Value="([^"]*)"\s*/>', text)


def main():
    if len(sys.argv) < 3:
        print(__doc__); return 1
    prefix, cmd, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
    zp = prefix_state(prefix)
    if not os.path.exists(zp):
        print(f"no user state at {zp}"); return 1

    if cmd == "save":
        shutil.copyfile(zp, rest[0]); print(f"saved {zp} -> {rest[0]}"); return 0
    if cmd == "load":
        tmp = zp + ".asloaded"
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr(MEMBER, open(rest[0], encoding="utf-8-sig").read())
        os.replace(tmp, zp); print(f"loaded {rest[0]} -> {zp}"); return 0

    text = read(zp)
    if cmd == "list":
        for k, v in entries(text):
            print(f"  {k} = {v if len(v) <= 120 else v[:117] + '…'}")
        return 0
    if cmd == "get":
        for k, v in entries(text):
            if k == rest[0]:
                print(v); return 0
        print(f"(absent) {rest[0]}"); return 1
    if cmd == "set":
        key, val = rest[0], rest[1]
        if re.search(rf'<Entry Type="{re.escape(key)}" Value="[^"]*"\s*/>', text):
            text = re.sub(rf'<Entry Type="{re.escape(key)}" Value="[^"]*"\s*/>',
                          f'<Entry Type="{key}" Value="{val}" />', text)
        else:
            text = text.replace("</Entries>", f'<Entry Type="{key}" Value="{val}" />' + "</Entries>")
        write(zp, text); print(f"set {key} = {val}"); return 0
    if cmd == "del":
        key = rest[0]
        new = re.sub(rf'<Entry Type="{re.escape(key)}" Value="[^"]*"\s*/>', "", text)
        if new == text:
            print(f"(absent) {key}"); return 1
        write(zp, new); print(f"deleted {key}"); return 0
    print(__doc__); return 1


if __name__ == "__main__":
    sys.exit(main())
