#!/usr/bin/env python3
"""Send a key chord (held modifiers) to the libvirt guest via QMP input-send-event.

Needed because the Windows UAC consent UI runs on the secure desktop: it is NOT captured by
`virsh screenshot` (verified here), so it cannot be clicked by coordinates read off a frame.
Modifiers must be held across the key press, which a batch of QMP taps does not do.

usage: vmhotkey.py alt+y            # Alt+Y  (UAC 'Yes' accelerator)
       vmhotkey.py ctrl+shift+esc
       vmhotkey.py ret  left  tab   # space-separated taps, no modifier held

QMP qcode names: alt, ctrl, shift, meta, ret, esc, tab, space, left, right, up, down,
                 a..z, 0..9, f1..f12, delete, backspace
"""
import json
import subprocess
import sys
import time

DOMAIN = "win11"
MODS = {"alt": "alt", "lalt": "alt", "ctrl": "ctrl", "lctrl": "ctrl",
        "shift": "shift", "lshift": "shift", "meta": "meta", "win": "meta"}


def qmp(events):
    cmd = json.dumps({"execute": "input-send-event", "arguments": {"events": events}})
    subprocess.run(["virsh", "qemu-monitor-command", DOMAIN, cmd],
                   check=True, capture_output=True)


def kev(qcode, down):
    return {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": qcode}}}


def tap(qcode, mods):
    for m in mods:
        qmp([kev(m, True)])
    time.sleep(0.05)
    qmp([kev(qcode, True)])
    time.sleep(0.05)
    qmp([kev(qcode, False)])
    time.sleep(0.05)
    for m in reversed(mods):
        qmp([kev(m, False)])


def main():
    argv = sys.argv[1:]
    if not argv:
        print(__doc__)
        raise SystemExit(2)
    if " " in argv[0] and len(argv) == 1:
        argv = argv[0].split()
    for spec in argv:
        parts = spec.lower().split("+")
        qcode = parts[-1]
        mods = [MODS[p] for p in parts[:-1]]
        unknown = [p for p in parts[:-1] if p not in MODS]
        if unknown:
            raise SystemExit("unknown modifier(s): %s" % ",".join(unknown))
        tap(qcode, mods)
        print("sent %s" % spec)
        time.sleep(0.2)


if __name__ == "__main__":
    main()
