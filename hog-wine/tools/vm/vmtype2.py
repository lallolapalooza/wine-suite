#!/usr/bin/env python3
"""Type a string into the libvirt guest with `virsh send-key`, one group per keystroke.

Why not vmkey.py/vmtype.py: those send one QMP/virsh call per character and a stuck modifier
leaks into the following keys.  libvirt's `virDomainSendKey` presses every listed keycode, holds
them for --holdtime ms and releases them in reverse order — so a modifier listed before its key
is held for that key only, which is exactly the semantics a string typer needs.

usage: vmtype2.py <text> [--enter] [--holdtime MS] [--gap MS] [--domain NAME]
"""
import subprocess
import sys
import time

DOMAIN = "win11"
HOLD = 20
GAP = 40

BASE = {
    " ": "KEY_SPACE", "-": "KEY_MINUS", "=": "KEY_EQUAL", "[": "KEY_LEFTBRACE",
    "]": "KEY_RIGHTBRACE", "\\": "KEY_BACKSLASH", ";": "KEY_SEMICOLON",
    "'": "KEY_APOSTROPHE", "`": "KEY_GRAVE", ",": "KEY_COMMA", ".": "KEY_DOT",
    "/": "KEY_SLASH", "0": "KEY_0", "1": "KEY_1", "2": "KEY_2", "3": "KEY_3",
    "4": "KEY_4", "5": "KEY_5", "6": "KEY_6", "7": "KEY_7", "8": "KEY_8", "9": "KEY_9",
}
SHIFTED_BASE = {
    "!": "KEY_1", "@": "KEY_2", "#": "KEY_3", "$": "KEY_4", "%": "KEY_5", "^": "KEY_6",
    "&": "KEY_7", "*": "KEY_8", "(": "KEY_9", ")": "KEY_0", "_": "KEY_MINUS",
    "+": "KEY_EQUAL", "{": "KEY_LEFTBRACE", "}": "KEY_RIGHTBRACE", "|": "KEY_BACKSLASH",
    ":": "KEY_SEMICOLON", '"': "KEY_APOSTROPHE", "<": "KEY_COMMA", ">": "KEY_DOT",
    "?": "KEY_SLASH", "~": "KEY_GRAVE",
}
NAMED = {
    "\n": "KEY_ENTER", "\r": "KEY_ENTER", "\t": "KEY_TAB", "\x1b": "KEY_ESC",
}


def code_for(ch):
    if ch in NAMED:
        return [NAMED[ch]]
    if ch.isalpha():
        if ch.isupper():
            return ["KEY_LEFTSHIFT", "KEY_" + ch.upper()]
        return ["KEY_" + ch.upper()]
    if ch in SHIFTED_BASE:
        return ["KEY_LEFTSHIFT", SHIFTED_BASE[ch]]
    if ch in BASE:
        return [BASE[ch]]
    raise SystemExit("no keycode for %r" % ch)


def send(keys, domain, hold):
    subprocess.run(["virsh", "send-key", domain, "--holdtime", str(hold)] + keys,
                   check=True, capture_output=True)


def main():
    args = sys.argv[1:]
    text = args[0]
    enter = "--enter" in args
    hold = HOLD
    gap = GAP
    domain = DOMAIN
    if "--holdtime" in args:
        hold = int(args[args.index("--holdtime") + 1])
    if "--gap" in args:
        gap = int(args[args.index("--gap") + 1])
    if "--domain" in args:
        domain = args[args.index("--domain") + 1]
    for ch in text:
        send(code_for(ch), domain, hold)
        time.sleep(gap / 1000.0)
    if enter:
        send(["KEY_ENTER"], domain, hold)


if __name__ == "__main__":
    main()
