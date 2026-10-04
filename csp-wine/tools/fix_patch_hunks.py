#!/usr/bin/env python3
"""Repair a unified diff whose hunk headers disagree with their bodies.

The upstream CSPenguin `wine-mf-encoder-support.patch` has hunk headers that do not
match the hunks they introduce (patch(1) rejects it: "malformed patch at line 30").
The bodies are complete; only the counts are wrong.  This recomputes every hunk
header from its body, preserving the original start lines and the trailing
function/section text.

usage: fix_patch_hunks.py <in.patch> [out.patch]
"""
import re
import sys

HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$")


def split_body(lines, i):
    """Return (body_lines, next_index) for the hunk starting at header line i."""
    j = i + 1
    body = []
    while j < len(lines):
        line = lines[j]
        if line.startswith("diff --git ") or line.startswith("@@ ") or HUNK_RE.match(line):
            break
        body.append(line)
        j += 1
    # trailing empty element from the final newline is not part of any hunk
    return body, j


def main():
    src, dst = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
    lines = open(src, encoding="utf-8", errors="replace").read().split("\n")
    out = []
    i = 0
    repaired = 0
    while i < len(lines):
        m = HUNK_RE.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        old_start, new_start, tail = m.group(1), m.group(3), m.group(5)
        body, nxt = split_body(lines, i)
        old_n = new_n = 0
        for line in body:
            if line.startswith("\\"):        # "\ No newline at end of file"
                continue
            if line.startswith("+"):
                new_n += 1
            elif line.startswith("-"):
                old_n += 1
            else:                            # context (' ' or, rarely, bare '')
                old_n += 1
                new_n += 1
        new_hdr = f"@@ -{old_start},{old_n} +{new_start},{new_n} @@{tail}"
        if new_hdr != lines[i]:
            repaired += 1
        out.append(new_hdr)
        out.extend(body)
        i = nxt
    open(dst, "w", encoding="utf-8").write("\n".join(out))
    print(f"repaired {repaired} hunk header(s) -> {dst}")


if __name__ == "__main__":
    main()
