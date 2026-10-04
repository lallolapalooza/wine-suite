#!/usr/bin/env python3
"""relaydiff.py - normalise and diff two very different Win32 API call logs.

It understands two log grammars:

  * Wine ``WINEDEBUG=+relay`` output, e.g.::

        12345.678:0009:Call KERNEL32.CreateFileW(0012ab30 "C:\\\\x",00000001,...) ret=7f0012345678
        12345.679:0009:Ret  KERNEL32.CreateFileW() retval=00000040 ret=7f0012345678
        12345.680:0009:fixme:heap:RtlSetHeapInformation ... 0 stub

    The optional ``+timestamp`` prefix (``12345.678:``), the optional ``+pid``
    prefix, the 4-hex thread id, nested leading indentation and both the
    ``dll.func`` and ``dll!func`` spellings are accepted.

  * The apitrace grammar emitted by the Windows-side ApiTracer::

        12 3484 KERNEL32!CreateFileW (arg0=0x12ab30, arg1="C:\\\\x") -> 0x40

Sub-commands
------------
``wine-log FILE``
    Normalise a relay log to ``<tid> <dll>!<func>(<canonical args>)`` lines.
``wine-log --errors FILE``
    Emit only calls whose return value is a failure NTSTATUS / Win32 error,
    followed by a summary of the most frequent ``err:`` / ``fixme:`` messages.
``wine-log --tail N FILE``
    Emit only the last *N* calls (crash/hang tail); combine with ``--errors``
    to keep only the last *N* failing calls.  ``wine-log --modules a,b FILE``
    restricts the output to calls belonging to the named DLL modules.
``diff A B``
    Normalise both logs (pointers -> ``PTR``, small integers -> canonical
    hex, strings kept), collapse consecutive repeats to ``call xN`` and report
    the call sequences present in one log but not the other, plus a
    per-function call-count table.

The parsers stream their input line by line; a 2 GiB relay log is processed
without ever being held in memory.  Only ``diff`` accumulates the (much
smaller) normalised token stream, and it is bounded by ``--max-calls``.
"""

from __future__ import annotations

import argparse
import contextlib
import difflib
import re
import sys
from collections import Counter, defaultdict, deque

# --------------------------------------------------------------------------- #
# tuning knobs
# --------------------------------------------------------------------------- #

#: Hex/decimal values strictly above this are considered "pointer-looking" and
#: replaced by ``PTR`` during normalisation.  Values at or below it are kept.
POINTER_MIN = 0x10000

DEFAULT_MAX_CALLS = 5_000_000
MAX_STACK = 1_000_000  # runaway guard for malformed Call-without-Ret logs

# --------------------------------------------------------------------------- #
# error tables
# --------------------------------------------------------------------------- #

NTSTATUS_NAMES = {
    0x80000005: "STATUS_BUFFER_OVERFLOW",
    0x8000001A: "STATUS_NO_MORE_ENTRIES",
    0xC0000001: "STATUS_UNSUCCESSFUL",
    0xC0000002: "STATUS_NOT_IMPLEMENTED",
    0xC0000005: "STATUS_ACCESS_VIOLATION",
    0xC0000008: "STATUS_INVALID_HANDLE",
    0xC000000D: "STATUS_INVALID_PARAMETER",
    0xC000000F: "STATUS_NO_SUCH_FILE",
    0xC0000010: "STATUS_INVALID_DEVICE_REQUEST",
    0xC0000017: "STATUS_NO_MEMORY",
    0xC0000022: "STATUS_ACCESS_DENIED",
    0xC0000023: "STATUS_BUFFER_TOO_SMALL",
    0xC0000033: "STATUS_OBJECT_NAME_INVALID",
    0xC0000034: "STATUS_OBJECT_NAME_NOT_FOUND",
    0xC0000035: "STATUS_OBJECT_NAME_COLLISION",
    0xC000003A: "STATUS_OBJECT_PATH_NOT_FOUND",
    0xC000003B: "STATUS_OBJECT_PATH_SYNTAX_BAD",
    0xC000007A: "STATUS_PROCEDURE_NOT_FOUND",
    0xC000007B: "STATUS_INVALID_IMAGE_FORMAT",
    0xC000009A: "STATUS_INSUFFICIENT_RESOURCES",
    0xC00000BB: "STATUS_NOT_SUPPORTED",
    0xC00000C9: "STATUS_DEVICE_NOT_CONNECTED",
    0xC0000121: "STATUS_DISK_FULL",
    0xC0000135: "STATUS_DLL_NOT_FOUND",
    0xC0000138: "STATUS_ORDINAL_NOT_FOUND",
    0xC0000139: "STATUS_ENTRYPOINT_NOT_FOUND",
    0xC0000142: "STATUS_DLL_INIT_FAILED",
    0xC0000225: "STATUS_NOT_FOUND",
    0xC000026C: "STATUS_DRIVER_UNABLE_TO_LOAD",
}

WIN32_ERRORS = {
    2: "ERROR_FILE_NOT_FOUND",
    3: "ERROR_PATH_NOT_FOUND",
    4: "ERROR_TOO_MANY_OPEN_FILES",
    5: "ERROR_ACCESS_DENIED",
    6: "ERROR_INVALID_HANDLE",
    8: "ERROR_NOT_ENOUGH_MEMORY",
    13: "ERROR_INVALID_DATA",
    14: "ERROR_OUTOFMEMORY",
    15: "ERROR_INVALID_DRIVE",
    17: "ERROR_NOT_SAME_DEVICE",
    18: "ERROR_NO_MORE_FILES",
    19: "ERROR_WRITE_PROTECT",
    21: "ERROR_NOT_READY",
    23: "ERROR_CRC",
    24: "ERROR_BAD_LENGTH",
    27: "ERROR_FILE_CORRUPT",
    28: "ERROR_DISK_FULL",
    32: "ERROR_SHARING_VIOLATION",
    33: "ERROR_LOCK_VIOLATION",
    36: "ERROR_SHARING_BUFFER_EXCEEDED",
    38: "ERROR_HANDLE_EOF",
    50: "ERROR_NOT_SUPPORTED",
    53: "ERROR_BAD_NETPATH",
    67: "ERROR_BAD_NET_NAME",
    80: "ERROR_FILE_EXISTS",
    87: "ERROR_INVALID_PARAMETER",
    109: "ERROR_BROKEN_PIPE",
    116: "ERROR_INVALID_TARGET_HANDLE",
    120: "ERROR_CALL_NOT_IMPLEMENTED",
    122: "ERROR_INSUFFICIENT_BUFFER",
    123: "ERROR_INVALID_NAME",
    126: "ERROR_MOD_NOT_FOUND",
    127: "ERROR_PROC_NOT_FOUND",
    145: "ERROR_DIR_NOT_EMPTY",
    161: "ERROR_BAD_PATHNAME",
    183: "ERROR_ALREADY_EXISTS",
    203: "ERROR_ENVVAR_NOT_FOUND",
    206: "ERROR_FILENAME_EXCED_RANGE",
    215: "ERROR_NESTING_NOT_ALLOWED",
    234: "ERROR_MORE_DATA",
    259: "ERROR_NO_MORE_ITEMS",
    267: "ERROR_DIRECTORY",
    487: "ERROR_INVALID_ADDRESS",
    998: "ERROR_NOACCESS",
    1008: "ERROR_NO_TOKEN",
    1062: "ERROR_SERVICE_NOT_ACTIVE",
    1063: "ERROR_SERVICE_DISABLED",
    1157: "ERROR_DLL_NOT_FOUND",
    1260: "ERROR_ACCESS_DISABLED_BY_POLICY",
    1813: "ERROR_RESOURCE_TYPE_NOT_FOUND",
    1919: "ERROR_NO_MORE_NETWORK_CONNECTIONS",
    1920: "ERROR_CANT_ACCESS_FILE",
    1921: "ERROR_CANT_RESOLVE_FILENAME",
    10013: "WSAEACCES",
    10022: "WSAEINVAL",
    10024: "WSAEMFILE",
    10038: "WSAENOTSOCK",
    10048: "WSAEADDRINUSE",
    10061: "WSAECONNREFUSED",
    10065: "WSAEHOSTUNREACH",
}

# --------------------------------------------------------------------------- #
# lexing helpers
# --------------------------------------------------------------------------- #

#: ``<timestamp>?:<pid>:<tid>:``  (pid present only with +pid; timestamp with
#: +timestamp).  The trailing group is whatever follows the last ``:``.
HDR_RE = re.compile(r"^(?:(\d+\.\d+):)?((?:[0-9a-fA-F]{1,8}:)+)(.*)$")

#: ``fixme:channel:function message`` / ``err:channel:function message``.
DBG_RE = re.compile(r"^(fixme|err|warn|trace):([^:]*):([^\s]*)\s?(.*)$")

HEX0X_RE = re.compile(r"^([+-]?)0[xX]([0-9a-fA-F]+)$")
DEC_RE = re.compile(r"^[+-]?\d+$")
BAREHEX_RE = re.compile(r"^[0-9a-fA-F]+$")
NAME_EQ_RE = re.compile(r"([A-Za-z_][A-Za-z0-9_.\[\]]*)=(.*)$", re.S)
PTR_STR_RE = re.compile(r'^(\S+)\s+((?:L)?".*")$', re.S)
RETVAL_RE = re.compile(r"retval=([0-9a-fA-F]+)")
RETADDR_RE = re.compile(r"\bret=([0-9a-fA-F]+)")


def scan_paren(s: str, start: int) -> int:
    """Index of the ``)`` matching ``s[start] == '('`` (quote/brace aware)."""
    depth = 0
    in_str = False
    esc = False
    i = start
    n = len(s)
    while i < n:
        c = s[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c in "([{<":
                depth += 1
            elif c in ")]}>":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def split_args(s: str):
    """Split a relay/apitrace argument string on top-level commas.

    Quotes, escapes and bracketed values are respected, and Wine's
    ``<ptr> "string"`` argument is expanded into two positional arguments so
    that it lines up with apitrace's ``arg0=..., arg1="..."`` layout.
    """
    if not s.strip():
        return []
    out = []
    cur = []
    depth = 0
    in_str = False
    esc = False
    for c in s:
        if in_str:
            cur.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
            cur.append(c)
            continue
        if c in "([{<":
            depth += 1
            cur.append(c)
            continue
        if c in ")]}>":
            depth -= 1
            cur.append(c)
            continue
        if c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
            continue
        cur.append(c)
    out.append("".join(cur).strip())

    flat = []
    for a in out:
        if not a:
            continue
        if not a.startswith(('"', 'L"')):
            m = PTR_STR_RE.match(a)
            if m:
                flat.append(m.group(1))
                flat.append(m.group(2))
                continue
        flat.append(a)
    return flat


def norm_string(tok: str) -> str:
    """Decode a Wine ``debugstr`` quoted string and re-escape it canonically."""
    wide = tok.startswith('L"')
    s = tok[1:] if wide else tok
    if len(s) < 2 or s[0] != '"' or s[-1] != '"':
        return tok
    inner = s[1:-1]
    out = []
    i = 0
    n = len(inner)
    while i < n:
        c = inner[i]
        if c == "\\" and i + 1 < n:
            d = inner[i + 1]
            if d in '\\"':
                out.append(d)
                i += 2
                continue
            if d == "n":
                out.append("\n")
                i += 2
                continue
            if d == "r":
                out.append("\r")
                i += 2
                continue
            if d == "t":
                out.append("\t")
                i += 2
                continue
            if d == "x" and i + 3 < n and re.match(r"[0-9a-fA-F]{2}", inner[i + 2 : i + 4]):
                out.append(chr(int(inner[i + 2 : i + 4], 16)))
                i += 4
                continue
            out.append(c)
            i += 1
        else:
            out.append(c)
            i += 1
    text = "".join(out)
    text = text.replace("\\", "\\\\").replace('"', '\\"')
    return ("L" if wide else "") + '"' + text + '"'


def normalize_arg(tok: str, strip_names: bool = False, drop_wide: bool = False) -> str:
    """Canonical form of a single argument.

    ``name=value`` prefixes are dropped when *strip_names* is set, values above
    :data:`POINTER_MIN` become ``PTR``, smaller integers become canonical hex
    (Wine prints every integer argument as bare hex, so bare digit runs are
    read as hex too) and strings are re-escaped.  ``drop_wide`` folds wide
    strings onto narrow ones (useful when comparing Wine against apitrace).
    """
    tok = tok.strip()
    if not tok:
        return tok
    if strip_names and not tok.startswith(('"', 'L"')):
        m = NAME_EQ_RE.match(tok)
        if m:
            tok = m.group(2).strip()
    if tok.startswith('"') or tok.startswith('L"'):
        s = norm_string(tok)
        if drop_wide and s.startswith('L"'):
            s = s[1:]
        return s
    if tok.startswith("{") and tok.endswith("}"):
        return "{" + ",".join(normalize_arg(p, drop_wide=drop_wide) for p in split_args(tok[1:-1])) + "}"
    m = PTR_STR_RE.match(tok)
    if m and not tok.startswith(('"', 'L"')):
        return normalize_arg(m.group(1), drop_wide=drop_wide) + " " + normalize_arg(m.group(2), drop_wide=drop_wide)
    m = HEX0X_RE.match(tok)
    if m:
        v = int(m.group(2), 16)
        if m.group(1) == "-":
            v = -v
        return f"0x{v:x}" if -POINTER_MIN < v < POINTER_MIN else "PTR"
    if tok[:1] in "+-" and DEC_RE.match(tok):
        v = int(tok, 10)
        return str(v) if -POINTER_MIN < v < POINTER_MIN else "PTR"
    if BAREHEX_RE.match(tok):
        # Wine prints every integer argument as bare hex (%08lx style).
        v = int(tok, 16)
        return f"0x{v:x}" if v < POINTER_MIN else "PTR"
    return tok


def canon_display(name: str) -> str:
    """``KERNEL32.CreateFileW`` / ``kernel32!CreateFileW`` -> ``KERNEL32!CreateFileW``."""
    if "!" in name:
        dll, func = name.split("!", 1)
    elif "." in name:
        dll, func = name.split(".", 1)
    else:
        return name
    return dll + "!" + func


def canon_key(name: str) -> str:
    return canon_display(name).lower()


# --------------------------------------------------------------------------- #
# line parsers
# --------------------------------------------------------------------------- #

def parse_relay_line(line: str):
    """Parse one ``+relay`` line into a record dict, or return ``None``."""
    line = line.rstrip("\n").rstrip("\r")
    tid = None
    m = HDR_RE.match(line)
    if m:
        tid = m.group(2).rstrip(":").split(":")[-1]
        rest = m.group(3)
    else:
        rest = line
    rest = rest.lstrip("\x01 \t")
    if not rest:
        return None

    word = rest.split(None, 1)[0].lower()
    if word in ("call", "ret"):
        body = rest[len(rest.split(None, 1)[0]) :].lstrip()
        if word == "call":
            lp = body.find("(")
            if lp < 0:
                name = body.strip()
                return {"kind": "call", "tid": tid, "name": name, "args": [], "ret": None}
            name = body[:lp].strip()
            close = scan_paren(body, lp)
            if close < 0:
                return None
            args = split_args(body[lp + 1 : close])
            tail = body[close + 1 :]
            ra = RETADDR_RE.search(tail)
            return {
                "kind": "call",
                "tid": tid,
                "name": name,
                "args": args,
                "ret": int(ra.group(1), 16) if ra else None,
            }
        # Ret
        lp = body.find("(")
        if lp < 0:
            return None
        name = body[:lp].strip()
        close = scan_paren(body, lp)
        tail = body[close + 1 :] if close >= 0 else ""
        rv = RETVAL_RE.search(tail)
        return {
            "kind": "ret",
            "tid": tid,
            "name": name,
            "retval": int(rv.group(1), 16) if rv else None,
        }

    dm = DBG_RE.match(rest)
    if dm:
        return {"kind": "msg", "cls": dm.group(1), "channel": dm.group(2), "func": dm.group(3), "msg": dm.group(4)}
    return None


def parse_apitrace_line(line: str):
    """Parse ``<seq> <tid> <dll>!<func> (arg=..) -> 0x..``."""
    s = line.strip()
    m = re.match(r"^(\d+)\s+(\d+)\s+(\S+?)\s*\(", s)
    if not m:
        return None
    name = m.group(3)
    if "!" not in name and "." not in name:
        return None
    lp = m.end() - 1
    close = scan_paren(s, lp)
    if close < 0:
        return None
    args = split_args(s[lp + 1 : close])
    tail = s[close + 1 :]
    rv = None
    rm = re.search(r"->\s*(0x[0-9a-fA-F]+|[+-]?\d+|\S+)", tail)
    if rm:
        tok = rm.group(1)
        try:
            rv = int(tok, 16) if tok.lower().startswith("0x") else int(tok, 10)
        except ValueError:
            rv = None
    return {"kind": "call", "tid": m.group(2), "seq": int(m.group(1)), "name": name, "args": args, "retval": rv}


def parse_wineout_line(line: str):
    """Parse already-normalised ``<tid> <dll>!<func>(...)`` output."""
    s = line.strip()
    m = re.match(r"^([0-9a-fA-F]{1,8})\s+(\S+?)\s*\(", s)
    if not m:
        return None
    name = m.group(2)
    if "!" not in name and "." not in name:
        return None
    lp = m.end() - 1
    close = scan_paren(s, lp)
    if close < 0:
        return None
    return {"kind": "call", "tid": m.group(1), "name": name, "args": split_args(s[lp + 1 : close]), "retval": None}


def _iter_file(f):
    for line in f:
        if not line.strip():
            continue
        try:
            rec = None
            form = None
            if ":" in line[:13]:
                rec = parse_relay_line(line)
                if rec:
                    form = "relay"
            if rec is None:
                rec = parse_apitrace_line(line)
                if rec:
                    form = "apitrace"
            if rec is None:
                rec = parse_wineout_line(line)
                if rec:
                    form = "wineout"
            if rec is not None:
                yield form, rec
        except Exception:
            # A garbage or truncated line must never abort a multi-GB scan.
            continue


def iter_records(path: str):
    """Yield ``(form, record)`` for every recognised line (streaming)."""
    if path == "-":
        yield from _iter_file(sys.stdin)
    else:
        with open(path, "r", errors="replace") as f:
            yield from _iter_file(f)


# --------------------------------------------------------------------------- #
# wine-log sub-command
# --------------------------------------------------------------------------- #

def message_key(rec) -> str:
    prefix = rec["cls"] + ":" + rec["channel"] + ((":" + rec["func"]) if rec["func"] else "")
    msg = rec["msg"]
    msg = re.sub(r"0x[0-9a-fA-F]+", "#", msg)
    msg = re.sub(r"\b[0-9a-fA-F]{8,}\b", "#", msg)
    msg = re.sub(r"\b\d+\b", "#", msg)
    msg = re.sub(r"\s+", " ", msg).strip()
    return (prefix + " " + msg).strip()


def pop_matching(stack, name):
    if not stack:
        return None
    key = canon_key(name)
    for i in range(len(stack) - 1, -1, -1):
        if canon_key(stack[i]["name"]) == key:
            return stack.pop(i)
    return stack.pop()


def classify_retval(v: int, include_zero: bool = False):
    """Return ``(kind, symbolic_name_or_None)`` for a failing return value."""
    low = v & 0xFFFFFFFF
    if low >= 0x80000000:
        return "NTSTATUS", NTSTATUS_NAMES.get(low)
    if 0 < low <= 0xFFFF and low in WIN32_ERRORS:
        return "Win32", WIN32_ERRORS[low]
    if include_zero and v == 0:
        return "ZERO", None
    return None


def render_call(rec) -> str:
    tid = rec.get("tid") or "????"
    args = ",".join(normalize_arg(a) for a in rec["args"])
    return f"{tid} {canon_display(rec['name'])}({args})"


def render_failure(tid, call, retval, cls) -> str:
    kind, sym = cls
    args = ",".join(normalize_arg(a) for a in call["args"])
    label = kind + ((" " + sym) if sym else "")
    width = 8 if retval <= 0xFFFFFFFF else 0
    shown = f"0x{retval:0{width}x}" if width else f"0x{retval:x}"
    return f"{tid} {canon_display(call['name'])}({args}) -> {shown} [{label}]"


@contextlib.contextmanager
def open_out(path: str):
    if path == "-":
        yield sys.stdout
    else:
        with open(path, "w") as f:
            yield f


def cmd_wine_log(args) -> int:
    modules = None
    if args.modules:
        modules = {m.strip().lower() for m in args.modules.split(",") if m.strip()} or None

    def mod_ok(name: str) -> bool:
        if modules is None:
            return True
        return canon_display(name).split("!", 1)[0].lower() in modules

    stacks = defaultdict(list)
    dropped = 0
    msg_counter = Counter()
    total_msgs = 0
    n_fail = 0
    tail = deque(maxlen=args.tail) if args.tail is not None else None

    with open_out(args.out) as out:
        def emit(text: str) -> None:
            if tail is None:
                out.write(text + "\n")
            else:
                tail.append(text)

        for _form, rec in iter_records(args.file):
            kind = rec.get("kind")
            if kind == "msg":
                if rec["cls"] in ("err", "fixme"):
                    msg_counter[message_key(rec)] += 1
                    total_msgs += 1
                continue
            if kind not in ("call", "ret"):
                continue
            if not mod_ok(rec["name"]):
                continue
            tid = rec.get("tid") or "????"
            if kind == "call":
                if args.errors:
                    stack = stacks[tid]
                    if len(stack) < MAX_STACK:
                        stack.append(rec)
                    else:
                        dropped += 1
                else:
                    emit(render_call(rec))
                continue
            if not args.errors:
                continue
            stack = stacks.get(tid)
            if not stack:
                continue
            call = pop_matching(stack, rec["name"])
            if call is None or rec.get("retval") is None:
                continue
            cls = classify_retval(rec["retval"], args.include_zero)
            if cls is None:
                continue
            n_fail += 1
            emit(render_failure(tid, call, rec["retval"], cls))

        if tail is not None:
            for text in tail:
                out.write(text + "\n")

        if args.errors:
            out.write("\n")
            out.write(f"== err:/fixme: message summary ({len(msg_counter)} distinct, {total_msgs} total) ==\n")
            for key, count in msg_counter.most_common(args.top):
                out.write(f"{count:7d}  {key}\n")
            if dropped:
                out.write(f"# warning: {dropped} calls dropped (stack guard)\n")
            out.write(f"# total failing calls: {n_fail}\n")
    return 0


# --------------------------------------------------------------------------- #
# diff sub-command
# --------------------------------------------------------------------------- #

def load_diff_stream(path: str, max_calls: int):
    toks = []
    funcs = Counter()
    n = 0
    for _form, rec in iter_records(path):
        if rec.get("kind") != "call":
            continue
        key = canon_key(rec["name"])
        funcs[key] += 1
        nargs = [normalize_arg(a, strip_names=True, drop_wide=True) for a in rec["args"]]
        # Wine prints string arguments as "<ptr> \"str\""; apitrace prints only
        # "\"str\"".  The pointer is pure noise (always normalised to PTR), so
        # drop it to keep the positional argument lists comparable.
        kept = []
        for i, a in enumerate(nargs):
            if a == "PTR" and i + 1 < len(nargs) and nargs[i + 1].startswith('"'):
                continue
            kept.append(a)
        toks.append(key + "(" + ",".join(kept) + ")")
        n += 1
        if max_calls and n > max_calls:
            raise SystemExit(
                f"error: {path}: more than {max_calls} calls; raise --max-calls "
                f"(0 = keep everything in memory) or slice the log"
            )
    return toks, funcs


def collapse(tokens):
    """Collapse consecutive identical tokens into ``token xN``."""
    out = []
    for t in tokens:
        if out and out[-1][0] == t:
            out[-1][1] += 1
        else:
            out.append([t, 1])
    return [f"{t} x{n}" if n > 1 else t for t, n in out]


def diff_lines(tokens_a, tokens_b, max_report):
    ca = collapse(tokens_a)
    cb = collapse(tokens_b)
    sm = difflib.SequenceMatcher(None, ca, cb, autojunk=False)
    a_only, b_only = [], []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag in ("delete", "replace"):
            a_only.extend(ca[i1:i2])
        if tag in ("insert", "replace"):
            b_only.extend(cb[j1:j2])
    return ca, cb, a_only, b_only


def cmd_diff(args) -> int:
    toks_a, funcs_a = load_diff_stream(args.a, args.max_calls)
    toks_b, funcs_b = load_diff_stream(args.b, args.max_calls)
    _ca, _cb, a_only, b_only = diff_lines(toks_a, toks_b, args.max_report)

    out = sys.stdout
    out.write(f"# A = {args.a}  ({len(toks_a)} calls)\n")
    out.write(f"# B = {args.b}  ({len(toks_b)} calls)\n")
    out.write("\n")
    out.write(f"== call sequences in A not in B ({len(a_only)}) ==\n")
    if not a_only:
        out.write("  (none)\n")
    for i, t in enumerate(a_only):
        if i >= args.max_report:
            out.write(f"  ... {len(a_only) - args.max_report} more\n")
            break
        out.write("  " + t + "\n")
    out.write("\n")
    out.write(f"== call sequences in B not in A ({len(b_only)}) ==\n")
    if not b_only:
        out.write("  (none)\n")
    for i, t in enumerate(b_only):
        if i >= args.max_report:
            out.write(f"  ... {len(b_only) - args.max_report} more\n")
            break
        out.write("  " + t + "\n")

    out.write("\n")
    out.write("== per-function call counts ==\n")
    allf = sorted(set(funcs_a) | set(funcs_b), key=lambda k: (-(funcs_a[k] + funcs_b[k]), k))
    width = max((len(k) for k in allf), default=8)
    out.write("function".ljust(width) + "       A       B   delta\n")
    for k in allf[: args.func_limit]:
        a, b = funcs_a[k], funcs_b[k]
        out.write(f"{k.ljust(width)}  {a:6d}  {b:6d}  {b - a:+6d}\n")
    if len(allf) > args.func_limit:
        out.write(f"... {len(allf) - args.func_limit} more functions\n")
    return 0


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def nonneg_int(text: str) -> int:
    try:
        value = int(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f"{text!r} is not an integer")
    if value < 0:
        raise argparse.ArgumentTypeError("value must be >= 0")
    return value


def build_parser():
    p = argparse.ArgumentParser(
        prog="relaydiff.py",
        description="Normalise and diff Wine +relay logs against ApiTracer logs.",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    w = sub.add_parser("wine-log", help="normalise a WINEDEBUG=+relay log")
    w.add_argument("file", help="relay log file ('-' for stdin)")
    w.add_argument("--errors", action="store_true", help="emit only failing calls + err/fixme summary")
    w.add_argument("--include-zero", action="store_true", help="treat a zero return value as a failure")
    w.add_argument("--top", type=int, default=25, help="how many err:/fixme: entries to show (default 25)")
    w.add_argument("--tail", type=nonneg_int, default=None, metavar="N",
                   help="emit only the last N calls before the end of the log (crash/hang tail)")
    w.add_argument("--modules", default=None, metavar="a,b,c",
                   help="only include calls whose DLL module is listed (comma-separated, case-insensitive)")
    w.add_argument("--out", default="-", help="output file (default stdout)")
    w.set_defaults(func=cmd_wine_log)

    d = sub.add_parser("diff", help="normalise and diff two logs")
    d.add_argument("a", help="first log (relay or apitrace)")
    d.add_argument("b", help="second log (relay or apitrace)")
    d.add_argument("--max-calls", type=int, default=DEFAULT_MAX_CALLS,
                   help=f"per-file call cap (default {DEFAULT_MAX_CALLS}, 0 = unlimited)")
    d.add_argument("--max-report", type=int, default=300, help="max differing entries to list per side")
    d.add_argument("--func-limit", type=int, default=200, help="max rows in the per-function table")
    d.set_defaults(func=cmd_diff)
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
