#!/usr/bin/env python3
"""Hold a modifier down across a key press in the libvirt guest (QMP input-send-event).

usage: vmwin.py <mod> <key>   e.g. vmwin.py meta_l r   |  vmwin.py ctrl_l a
Modifiers: meta_l, ctrl_l, shift, alt_l
"""
import json
import subprocess
import sys
import time

DOMAIN = "win11"


def qmp(events):
    cmd = json.dumps({"execute": "input-send-event", "arguments": {"events": events}})
    subprocess.run(["virsh", "qemu-monitor-command", DOMAIN, cmd], check=True, capture_output=True)


def ev(code, down):
    return {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": code}}}


mod, key = sys.argv[1], sys.argv[2]
qmp([ev(mod, True)])
time.sleep(0.15)
qmp([ev(key, True)])
time.sleep(0.12)
qmp([ev(key, False)])
time.sleep(0.15)
qmp([ev(mod, False)])
print("sent %s+%s" % (mod, key))
