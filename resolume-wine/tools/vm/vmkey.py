#!/usr/bin/env python3
"""Send key combos to the libvirt guest via QMP input-send-event.

usage: vmkey.py 'alt+f4' 'ctrl+shift+esc' 'enter' 'win' 'ctrl+c' ...
Modifiers are held down for the whole press, so combos actually reach the guest
(vmkeys.py's {LALT} token releases Alt before the next key, which does NOT form a combo).

Keys: single characters, or names from the KEYMAP table below; 'win'|'meta'|'super' = left Windows key.
"""
import json
import subprocess
import sys
import time

DOMAIN = "win11"

KEYMAP = {
    "enter": "ret", "return": "ret", "esc": "esc", "escape": "esc", "tab": "tab",
    "space": "spc", "backspace": "backspace", "del": "delete", "delete": "delete",
    "up": "up", "down": "down", "left": "left", "right": "right",
    "home": "home", "end": "end", "pgup": "pgup", "pgdn": "pgdn",
    "f1": "f1", "f2": "f2", "f3": "f3", "f4": "f4", "f5": "f5", "f6": "f6",
    "f7": "f7", "f8": "f8", "f9": "f9", "f10": "f10", "f11": "f11", "f12": "f12",
    "print": "sysrq", "insert": "insert", "pause": "pause",
}
# QEMU qcodes: left modifiers are "ctrl"/"alt"/"shift" (no _l suffix); right ones are "_r".
MODMAP = {
    "alt": "alt", "lalt": "alt", "ralt": "alt_r",
    "ctrl": "ctrl", "lctrl": "ctrl", "rctrl": "ctrl_r",
    "shift": "shift", "lshift": "shift", "rshift": "shift_r",
    "win": "meta_l", "meta": "meta_l", "super": "meta_l",
}
# shifted symbols map to the base key + a shift modifier
SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
    "(": "9", ")": "0", "_": "minus", "+": "equal", "{": "leftbrace", "}": "rightbrace",
    "|": "backslash", ":": "semicolon", '"': "apostrophe", "<": "comma", ">": "dot",
    "?": "slash", "~": "grave",
}
PLAIN = {
    "-": "minus", "=": "equal", "[": "leftbrace", "]": "rightbrace", "\\": "backslash",
    ";": "semicolon", "'": "apostrophe", "`": "grave", ",": "comma", ".": "dot", "/": "slash",
    " ": "spc",
}


def qmp(events):
    cmd = json.dumps({"execute": "input-send-event", "arguments": {"events": events}})
    subprocess.run(["virsh", "qemu-monitor-command", DOMAIN, cmd],
                   check=True, capture_output=True)


def key_event(name, down):
    return {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": name}}}


def resolve(tok):
    """-> (qcode, needs_shift)"""
    t = tok.lower()
    if t in MODMAP:
        return MODMAP[t], False
    if t in KEYMAP:
        return KEYMAP[t], False
    if len(tok) == 1:
        if tok in SHIFTED:
            return SHIFTED[tok], True
        if tok.isalpha() and tok.isupper():
            return tok.lower(), True
        if tok in PLAIN:
            return PLAIN[tok], False
        return tok.lower(), False
    raise SystemExit("unknown key token: %r" % tok)


def press(combo, delay=0.05):
    parts = [p for p in combo.split("+") if p]
    codes = []
    shift = False
    for p in parts:
        c, s = resolve(p)
        shift = shift or s
        codes.append(c)
    mods = [c for c in codes if c in MODMAP.values()]
    keys = [c for c in codes if c not in MODMAP.values()]
    # send combined: modifiers down, keys down/up with shift if needed, modifiers up
    events = []
    for m in mods:
        events.append(key_event(m, True))
    if shift and "shift" not in mods:
        events.append(key_event("shift", True))
    if not keys:
        keys = mods
        mods = []
        events = [key_event(m, True) for m in keys]
    for k in keys:
        events.append(key_event(k, True))
    for k in reversed(keys):
        events.append(key_event(k, False))
    if shift and "shift" not in mods:
        events.append(key_event("shift", False))
    for m in reversed(mods):
        events.append(key_event(m, False))
    for i, ev in enumerate(events):
        qmp([ev])
        time.sleep(delay)


def type_text(text, delay=0.05):
    for ch in text:
        if ch.isupper():
            press("shift+" + ch.lower(), delay)
        elif ch in SHIFTED:
            press("shift+" + SHIFTED[ch], delay)
        else:
            press(ch, delay)


if __name__ == "__main__":
    args = sys.argv[1:]
    hold = 0.05
    if "--delay" in args:
        i = args.index("--delay")
        hold = float(args[i + 1])
        del args[i:i + 2]
    for a in args:
        press(a, hold)
    print("sent:", " ".join(args))
