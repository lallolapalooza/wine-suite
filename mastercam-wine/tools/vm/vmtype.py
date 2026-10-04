#!/usr/bin/env python3
"""Type text into the guest through virsh send-key (Linux keycode names).

usage: vmtype.py <text> [--enter] [--delay 0.02]
Special tokens: {WIN} {ENTER} {ESC} {TAB} {LCTRL} {LSHIFT} {LALT} {DEL} {BACKSPACE}
"""
import subprocess
import sys
import time

DOMAIN = "win11"

SHIFTED = {
    "!": "KEY_1", "@": "KEY_2", "#": "KEY_3", "$": "KEY_4", "%": "KEY_5",
    "^": "KEY_6", "&": "KEY_7", "*": "KEY_8", "(": "KEY_9", ")": "KEY_0",
    "_": "KEY_MINUS", "+": "KEY_EQUAL", "{": "KEY_LEFTBRACE", "}": "KEY_RIGHTBRACE",
    "|": "KEY_BACKSLASH", ":": "KEY_SEMICOLON", '"': "KEY_APOSTROPHE",
    "<": "KEY_COMMA", ">": "KEY_DOT", "?": "KEY_SLASH", "~": "KEY_GRAVE",
}
PLAIN = {
    "-": "KEY_MINUS", "=": "KEY_EQUAL", "[": "KEY_LEFTBRACE", "]": "KEY_RIGHTBRACE",
    "\\": "KEY_BACKSLASH", ";": "KEY_SEMICOLON", "'": "KEY_APOSTROPHE",
    "`": "KEY_GRAVE", ",": "KEY_COMMA", ".": "KEY_DOT", "/": "KEY_SLASH",
    " ": "KEY_SPACE",
}
SPECIAL = {
    "{WIN}": ["KEY_LEFTMETA"], "{ENTER}": ["KEY_ENTER"], "{ESC}": ["KEY_ESC"],
    "{TAB}": ["KEY_TAB"], "{DEL}": ["KEY_DELETE"], "{BACKSPACE}": ["KEY_BACKSPACE"],
    "{LCTRL}": ["KEY_LEFTCTRL"], "{LALT}": ["KEY_LEFTALT"], "{LSHIFT}": ["KEY_LEFTSHIFT"],
    "{UP}": ["KEY_UP"], "{DOWN}": ["KEY_DOWN"], "{LEFT}": ["KEY_LEFT"], "{RIGHT}": ["KEY_RIGHT"],
}


def keynames(text):
    out = []
    i = 0
    while i < len(text):
        for tok, names in SPECIAL.items():
            if text.startswith(tok, i):
                out.extend(names)
                i += len(tok)
                break
        else:
            ch = text[i]
            if "a" <= ch <= "z":
                out.append("KEY_" + ch.upper())
            elif "A" <= ch <= "Z":
                out.extend(["KEY_LEFTSHIFT", "KEY_" + ch])
            elif "0" <= ch <= "9":
                out.append("KEY_" + ch)
            elif ch in SHIFTED:
                out.extend(["KEY_LEFTSHIFT", SHIFTED[ch]])
            elif ch in PLAIN:
                out.append(PLAIN[ch])
            else:
                raise SystemExit("unsupported char: %r" % ch)
            i += 1
    return out


def main():
    args = [a for a in sys.argv[1:]]
    delay = 0.015
    if "--delay" in args:
        i = args.index("--delay")
        delay = float(args[i + 1])
        del args[i:i + 2]
    enter = "--enter" in args
    if enter:
        args.remove("--enter")
    text = " ".join(args)
    names = keynames(text)
    if enter:
        names.append("KEY_ENTER")
    for i in range(0, len(names), 8):
        batch = names[i:i + 8]
        subprocess.run(["virsh", "send-key", DOMAIN, "--codeset", "linux"] + batch,
                       check=True, capture_output=True)
        time.sleep(delay)
    print("typed %d keys" % len(names))


if __name__ == "__main__":
    main()
