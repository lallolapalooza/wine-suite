#!/usr/bin/env python3
"""Click (or move) the absolute pointer in the libvirt guest via QMP input-send-event.

The guest has a usb-tablet, so pointer coordinates are absolute in the 0..32767 range.

usage: vmclick.py <x> <y> [--screen WxH] [--move-only] [--right]
Coordinates are given in guest-screen pixels (default screen 1280x800).
"""
import json
import subprocess
import sys
import time

DOMAIN = "win11"


def qmp(events):
    cmd = json.dumps({"execute": "input-send-event", "arguments": {"events": events}})
    subprocess.run(["virsh", "qemu-monitor-command", DOMAIN, cmd], check=True, capture_output=True)


def move(x, y, w, h):
    ax = max(0, min(32767, int(round(x / w * 32767))))
    ay = max(0, min(32767, int(round(y / h * 32767))))
    qmp([{"type": "abs", "data": {"axis": "x", "value": ax}}])
    qmp([{"type": "abs", "data": {"axis": "y", "value": ay}}])


def click(x, y, w, h, button="left", move_only=False):
    move(x, y, w, h)
    time.sleep(0.2)
    if move_only:
        return
    qmp([{"type": "btn", "data": {"down": True, "button": button}}])
    time.sleep(0.05)
    qmp([{"type": "btn", "data": {"down": False, "button": button}}])


def main():
    args = sys.argv[1:]
    w, h = 1280, 800
    if "--screen" in args:
        i = args.index("--screen")
        w, h = (int(v) for v in args[i + 1].lower().split("x"))
        del args[i:i + 2]
    move_only = "--move-only" in args
    if move_only:
        args.remove("--move-only")
    button = "left"
    if "--right" in args:
        args.remove("--right")
        button = "right"
    x, y = int(args[0]), int(args[1])
    click(x, y, w, h, button, move_only)
    print("clicked %d,%d (%s)" % (x, y, "move" if move_only else button))


if __name__ == "__main__":
    main()
