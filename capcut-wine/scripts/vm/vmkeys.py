#!/usr/bin/env python3
"""Type text into the libvirt guest with correct modifier handling (QMP input-send-event).

usage: vmkeys.py <text> [--enter] [--delay 0.02]
Unlike send-key batches, shift/ctrl are held down for the whole key press, so shifted
characters (":", "\\", quotes) come out right.

Special tokens: {WIN} {ENTER} {ESC} {TAB} {LCTRL} {LSHIFT} {LALT} {DEL} {BACKSPACE} {UP} {DOWN} {LEFT} {RIGHT}
"""
import json
import subprocess
import sys
import time

DOMAIN = "win11"

PLAIN = {
    "-": "minus", "=": "equal", "[": "leftbrace", "]": "rightbrace", "\\": "backslash",
    ";": "semicolon", "'": "apostrophe", "`": "grave", ",": "comma", ".": "dot", "/": "slash",
    " ": "spc",
}
SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
    "(": "9", ")": "0", "_": "minus", "+": "equal", "{": "leftbrace", "}": "rightbrace",
    "|": "backslash", ":": "semicolon", '"': "apostrophe", "<": "comma", ">": "dot",
    "?": "slash", "~": "grave",
}
SPECIAL = {
    "{WIN}": ("meta_l", False), "{ENTER}": ("ret", False), "{ESC}": ("esc", False),
    "{TAB}": ("tab", False), "{DEL}": ("delete", False), "{BACKSPACE}": ("backspace", False),
    "{LCTRL}": ("ctrl_l", False), "{LSHIFT}": ("shift", False), "{LALT}": ("alt_l", False),
    "{UP}": ("up", False), "{DOWN}": ("down", False), "{LEFT}": ("left", False), "{RIGHT}": ("right", False),
}


def qmp(events):
    cmd = json.dumps({"execute": "input-send-event", "arguments": {"events": events}})
    subprocess.run(["virsh", "qemu-monitor-command", DOMAIN, cmd], check=True, capture_output=True)


def key_event(qcode, down):
    return {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": qcode}}}


def tap(qcode, shift=False):
    # separate QMP calls: a shift/key pair in one batch can be processed without the modifier held
    if shift:
        qmp([key_event("shift", True)])
    qmp([key_event(qcode, True)])
    qmp([key_event(qcode, False)])
    if shift:
        qmp([key_event("shift", False)])


def keys(text):
    out = []
    i = 0
    while i < len(text):
        for tok, (qc, _) in SPECIAL.items():
            if text.startswith(tok, i):
                out.append((qc, False))
                i += len(tok)
                break
        else:
            ch = text[i]
            if "a" <= ch <= "z":
                out.append((ch, False))
            elif "A" <= ch <= "Z":
                out.append((ch.lower(), True))
            elif "0" <= ch <= "9":
                out.append((ch, False))
            elif ch in SHIFTED:
                out.append((SHIFTED[ch], True))
            elif ch in PLAIN:
                out.append((PLAIN[ch], False))
            else:
                raise SystemExit("unsupported char: %r" % ch)
            i += 1
    return out


def main():
    args = sys.argv[1:]
    delay = 0.02
    if "--delay" in args:
        i = args.index("--delay")
        delay = float(args[i + 1])
        del args[i:i + 2]
    enter = "--enter" in args
    if enter:
        args.remove("--enter")
    text = " ".join(args)
    seq = keys(text)
    if enter:
        seq.append(("ret", False))
    for qc, shift in seq:
        tap(qc, shift)
        time.sleep(delay)
    print("typed %d keys" % len(seq))


if __name__ == "__main__":
    main()
