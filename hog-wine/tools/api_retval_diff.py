#!/usr/bin/env python3
"""api_retval_diff.py - return-value awareness on top of tools/relaydiff.py.

relaydiff.py normalises call *sequences* (names + arguments) and counts them, but its
``diff`` sub-command deliberately ignores return values, and ``wine-log --errors`` only
classifies failures inside a single log.  For the Wine-vs-Windows API diff the interesting
questions are:

  * which hooked call *succeeds on Windows and fails under Wine* (or vice versa), and
  * what are the last calls before each side stops?

This companion re-uses relaydiff's parsers/normalisers, so apitrace logs
(``<seq> <tid> DLL!Func (argN=0x..) -> 0x..``) and Wine ``+relay`` logs both work.

Because a 64-bit pointer return value can look like a 32-bit failure NTSTATUS (e.g. Wine's
base `0x6fffffb40000` masks to `0xffb40000`), the return-value comparison is *cfg-aware*:
pass the apihook ``--cfg`` file and only functions configured with ``:4`` return widths get
value-level failure classification; ``:8`` pointer returns are compared by nullness only
(NULL / INVALID_HANDLE_VALUE vs valid).

Sub-commands
------------
``tail FILE N``
    Last *N* calls, one per line, with the return value::
        <tid> DLL!Func(args) -> 0x... [tag]
    ``--fail`` keeps only calls whose value looks like a failure; ``--cfg`` improves the tag.
``retvals A B --cfg F``
    A = reference (Windows), B = suspect (Wine).  For every function present in both, compare
    the observed return values per normalised argument tuple and report the differences.
    ``--module a,b`` restricts to DLLs.
"""
from __future__ import annotations

import argparse
import sys
from collections import defaultdict

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import relaydiff as rd  # noqa: E402


# --------------------------------------------------------------------------- #
# cfg: func -> retwidth
# --------------------------------------------------------------------------- #

def load_cfg(path):
    """{lower(func): retwidth} from an apihook .cfg (0 = unknown)."""
    out = {}
    for line in open(path, errors="replace"):
        line = line.split("#", 1)[0].strip()
        if not line or line.startswith("~") or "!" not in line:
            continue
        _dll, rest = line.split("!", 1)
        at = rest.find("@")
        func = rest[:at] if at >= 0 else rest
        retw = 8
        if at >= 0:
            spec = rest[at + 1:]
            if ":" in spec:
                try:
                    retw = int(spec.rsplit(":", 1)[1])
                except ValueError:
                    retw = 8
        out[func.lower()] = retw
    return out


def is_failure(v, retw):
    """True when *v* looks like a failure for a function whose RAX width is *retw*.

    Zero is deliberately NOT treated as a failure: WAIT_OBJECT_0 == 0, ERROR_SUCCESS == 0 and
    many counts/DWORD getters legitimately return 0.  retw == 0 means the cfg declared the
    function void (`:0`), so there is no return value at all.
    """
    if v is None or retw == 0:
        return False
    if retw == 4:
        v &= 0xFFFFFFFF
        if v == 0xFFFFFFFF:  # -1: SOCKET_ERROR / INVALID_* / BOOL failure convention
            return True
        return rd.classify_retval(v) is not None
    # pointer / handle (or unknown): NULL and INVALID_HANDLE_VALUE are unambiguous failures
    return v == 0 or v == 0xFFFFFFFFFFFFFFFF


def tag(v, retw):
    if v is None:
        return "?"
    if retw == 0:
        return "void"
    if is_failure(v, retw):
        if retw == 4:
            cls = rd.classify_retval(v & 0xFFFFFFFF)
            if cls is not None:
                return cls[0] + ((":" + cls[1]) if cls[1] else "")
            return "FAIL-1" if v & 0xFFFFFFFF == 0xFFFFFFFF else "FAIL-0"
        return "NULL" if v == 0 else "INVALID_HANDLE_VALUE"
    return "ok"


def norm_tuple(rec):
    return tuple(rd.normalize_arg(a, strip_names=True, drop_wide=True) for a in rec["args"])


def ret_text(v):
    return "?" if v is None else f"0x{v:x}"


def mod_ok(rec, modules):
    if not modules:
        return True
    return rd.canon_display(rec["name"]).split("!", 1)[0].lower() in modules


# --------------------------------------------------------------------------- #
# sub-commands
# --------------------------------------------------------------------------- #

def cmd_tail(args):
    cfg = load_cfg(args.cfg) if args.cfg else {}
    recs = []
    for _form, rec in rd.iter_records(args.file):
        if rec.get("kind") != "call" or not mod_ok(rec, args.module):
            continue
        func = rd.canon_display(rec["name"]).split("!", 1)[-1].lower()
        retw = cfg.get(func, 0)
        if args.fail and not is_failure(rec.get("retval"), retw):
            continue
        recs.append((rec, retw))
    for rec, retw in recs[-args.n:]:
        rv = rec.get("retval")
        print(f"{rec.get('tid','????')} {rd.render_call(rec)} -> {ret_text(rv)} [{tag(rv, retw)}]")
    return 0


def collect(path, modules, cfg):
    per = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
    for _form, rec in rd.iter_records(path):
        if rec.get("kind") != "call" or not mod_ok(rec, modules):
            continue
        per[rd.canon_display(rec["name"])][norm_tuple(rec)][rec.get("retval")] += 1
    return per


def cmd_retvals(args):
    cfg = load_cfg(args.cfg) if args.cfg else {}
    A = collect(args.a, args.module, cfg)
    B = collect(args.b, args.module, cfg)
    only_a = sorted(set(A) - set(B))
    only_b = sorted(set(B) - set(A))
    print(f"# A(reference)={args.a}  functions={len(A)}")
    print(f"# B(suspect)  ={args.b}  functions={len(B)}")
    print(f"# cfg={args.cfg or '<none: 4-byte classification only>'}")
    print(f"\n== functions only in A ({len(only_a)}) ==")
    for f in only_a:
        print("  " + f)
    print(f"\n== functions only in B ({len(only_b)}) ==")
    for f in only_b:
        print("  " + f)

    print("\n== argument tuples whose return values differ ==")
    n = 0
    for f in sorted(set(A) & set(B)):
        retw = cfg.get(f.split("!", 1)[-1].lower(), 0)
        for atup in sorted(set(A[f]) | set(B[f])):
            ka = dict(A[f].get(atup, {}))
            kb = dict(B[f].get(atup, {}))
            if ka == kb:
                continue
            # compare only the failure/valid character when width is a pointer,
            # else compare the exact 32-bit value
            if retw == 4:
                sa = {(k & 0xFFFFFFFF) for k in ka}
                sb = {(k & 0xFFFFFFFF) for k in kb}
            else:
                sa = {("bad" if is_failure(k, retw) else "ok") for k in ka}
                sb = {("bad" if is_failure(k, retw) else "ok") for k in kb}
            if sa == sb:
                continue
            n += 1
            if n > args.max_report:
                continue
            print(f"  {f}({','.join(atup)})  [retw={retw}]")
            print("      A: " + ", ".join(f"{ret_text(k)}[{tag(k,retw)}]x{v}" for k, v in ka.items()))
            print("      B: " + ", ".join(f"{ret_text(k)}[{tag(k,retw)}]x{v}" for k, v in kb.items()))
    print(f"  ({n} differing argument tuples)")
    return 0


def build_parser():
    p = argparse.ArgumentParser(prog="api_retval_diff.py", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("tail", help="last N calls (optionally only failing ones) with return values")
    t.add_argument("file")
    t.add_argument("n", type=int)
    t.add_argument("--cfg", default=None)
    t.add_argument("--module", default=None)
    t.add_argument("--fail", action="store_true")
    t.set_defaults(func=cmd_tail)

    r = sub.add_parser("retvals", help="compare return values between two logs")
    r.add_argument("a", help="reference log (Windows)")
    r.add_argument("b", help="suspect log (Wine)")
    r.add_argument("--cfg", default=None)
    r.add_argument("--module", default=None)
    r.add_argument("--max-report", type=int, default=200)
    r.set_defaults(func=cmd_retvals)

    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    if getattr(args, "module", None):
        args.module = {m.strip().lower() for m in args.module.split(",") if m.strip()}
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
