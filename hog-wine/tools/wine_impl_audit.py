#!/usr/bin/env python3
"""Audit Wine *implementation bodies* for the APIs the app reaches.

A `@ stdcall` line in a .spec means "exported", not "works": Wine often ships a
function whose body is only `FIXME(...); return FALSE;`.  patches/local/0102-*
exists precisely because iphlpapi!NotifyIpInterfaceChange was in that state
while its .spec said stdcall.  This tool finds that class of gap.

Usage:
    wine_impl_audit.py --apis docs/_qt_win32_stubs.tsv ...
    wine_impl_audit.py --api-list a.txt --out docs/_wine_impl_audit.tsv

Input lines may be TSV (first column = API name) or plain names.
"""

import argparse
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qt_win32_index as qidx  # noqa: E402

COMMENT_BLOCK = re.compile(r"/\*.*?\*/", re.S)
COMMENT_LINE = re.compile(r"//[^\n]*")
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
DEFN = re.compile(r"\bWINAPI\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
NOISE_CALL = re.compile(
    r"^(FIXME|TRACE|WARN|ERR|FIXME_once|WARN_once|TRACE_once|todo_wine|"
    r"assert|ASSERT|UNIMPLEMENTED)\b")
RET_CONST = re.compile(
    r"^return\s+(FALSE|TRUE|NULL|nullptr|0|1|-1|E_NOTIMPL|E_FAIL|"
    r"S_OK|STATUS_SUCCESS|ERROR_CALL_NOT_IMPLEMENTED|"
    r"ERROR_NOT_SUPPORTED|ERROR_INVALID_PARAMETER|[A-Z_]*_NOT_IMPLEMENTED|"
    r"[A-Za-z_][A-Za-z0-9_]*E_NOTIMPL)\s*;")


def strip_comments(text):
    text = COMMENT_BLOCK.sub(" ", text)
    text = COMMENT_LINE.sub("", text)
    return text


def find_body(text, start):
    """Return the body of the function whose '(' is at/after `start`."""
    i = text.find("{", start)
    if i < 0:
        return None
    semi = text.find(";", start)
    if 0 <= semi < i:
        return None  # prototype, not a definition
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return None


def classify(body):
    """('stub'|'real', statements) for a function body."""
    b = strip_comments(body)
    b = STRING.sub('""', b)
    # split into statements on ';'
    stmts = [s.strip() for s in b.split(";") if s.strip()]
    real = []
    for s in stmts:
        s = " ".join(s.split())
        if not s:
            continue
        if NOISE_CALL.match(s) or RET_CONST.match(s + ";"):
            continue
        real.append(s)
    return ("stub" if not real else "real"), real


def build_defs(wine_root, wanted):
    """api -> list of (dll, file, lineno, body) for `wanted` APIs only."""
    defs = defaultdict(list)
    keep_dirs = qidx.API_DLLS | qidx.SECONDARY_DLLS | {"win32u", "ntdll", "wintab32"}
    dlls_dir = os.path.join(wine_root, "dlls")
    for entry in os.listdir(dlls_dir):
        ddir = os.path.join(dlls_dir, entry)
        if not os.path.isdir(ddir):
            continue
        if entry not in keep_dirs:
            continue
        for root, _dirs, files in os.walk(ddir):
            if os.sep + "tests" in root:
                continue
            for fn in files:
                if not fn.endswith((".c", ".cpp")):
                    continue
                path = os.path.join(root, fn)
                try:
                    with open(path, "r", errors="replace") as fh:
                        text = fh.read()
                except OSError:
                    continue
                for m in DEFN.finditer(text):
                    name = m.group(1)
                    if name not in wanted:
                        continue
                    body = find_body(text, m.end())
                    if body is None:
                        continue
                    lineno = text.count("\n", 0, m.start()) + 1
                    defs[name].append((entry, os.path.relpath(path, wine_root),
                                       lineno, body))
    return defs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apis", nargs="*", default=[])
    ap.add_argument("--api-list", action="append", default=[])
    ap.add_argument("--wine-root", default="/home/asdf/projects/hog-wine/wine-11.18")
    ap.add_argument("--out", default="")
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args()

    wanted = []
    for f in args.apis + args.api_list:
        with open(f, "r", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                wanted.append(line.split("\t")[0].split()[0])
    wanted = sorted(set(wanted))

    defs = build_defs(args.wine_root, set(wanted))
    rows = []
    for api in wanted:
        entries = defs.get(api)
        if not entries:
            continue
        verdicts = [classify(b) for (_d, _f, _l, b) in entries]
        if any(v[0] == "real" for v in verdicts):
            continue  # at least one real implementation exists
        dll, file, lineno, body = entries[0]
        rows.append((api, dll, file, lineno, " ".join(strip_comments(body).split())[:160]))

    if args.out:
        with open(args.out, "w") as fh:
            fh.write("api\tdll\tfile\tline\tbody\n")
            for r in rows:
                fh.write("\t".join(str(x) for x in r) + "\n")
    for r in rows:
        print("%-34s %s:%d  (%s)" % (r[0], r[2], r[3], r[1]))
        if args.show:
            print("        %s" % r[4])
    print("candidates audited: %d, FIXME-only bodies: %d" % (len(wanted), len(rows)))


if __name__ == "__main__":
    sys.exit(main())
