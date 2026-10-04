#!/usr/bin/env python3
"""Apply one plain-unified-diff patch to the current git work tree as a single commit.

Patches in this repo are NOT git-format-patch output: they are plain unified diffs,
optionally preceded by a free-text commit message (the message ends at the first
line starting with '--- a/' or 'diff --git ').  This helper extracts that message,
applies the diff with `git apply --index` (falling back to `git apply -3`), and
commits.  Prints a machine-readable verdict line.

Usage: apply_one.py <patchfile> [<subject-fallback>]
"""
import subprocess, sys, os, tempfile

patch = sys.argv[1]
fallback = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(patch)

raw = open(patch, 'rb').read().decode('utf-8', 'surrogateescape')
lines = raw.split('\n')

# find start of diff
start = None
for i, l in enumerate(lines):
    if l.startswith('--- a/') or l.startswith('--- a\\') or l.startswith('diff --git '):
        start = i
        break
if start is None:
    print("VERDICT FAIL no-diff-found %s" % patch); sys.exit(1)

msg_lines = [l for l in lines[:start] if l.strip() != '' or True]
# strip trailing blank lines of the message
while msg_lines and msg_lines[-1].strip() == '':
    msg_lines.pop()
msg = '\n'.join(msg_lines).strip()
if not msg:
    msg = fallback

diff_text = '\n'.join(lines[start:])
if not diff_text.endswith('\n'):
    diff_text += '\n'

with tempfile.NamedTemporaryFile('w', suffix='.patch', delete=False) as f:
    f.write(diff_text)
    tmp = f.name

def run(args):
    return subprocess.run(args, capture_output=True, text=True)

r = run(['git', 'apply', '--index', '--whitespace=nowarn', tmp])
variation = 'clean'
if r.returncode != 0:
    r2 = run(['git', 'apply', '--index', '--3way', '--whitespace=nowarn', tmp])
    if r2.returncode != 0:
        print("VERDICT FAIL apply %s\nSTDOUT:%s\nSTDERR:%s" % (patch, r.stdout+r2.stdout, r.stderr+r2.stderr))
        sys.exit(1)
    variation = '3way'
    r = r2

os.unlink(tmp)
# commit with message via file
with tempfile.NamedTemporaryFile('w', suffix='.msg', delete=False) as f:
    f.write(msg + '\n')
    mtmp = f.name
c = run(['git', 'commit', '-q', '-F', mtmp])
os.unlink(mtmp)
if c.returncode != 0:
    print("VERDICT FAIL commit %s\n%s" % (patch, c.stderr)); sys.exit(1)

sha = run(['git', 'rev-parse', '--short', 'HEAD']).stdout.strip()
subject = msg.split('\n')[0]
print("VERDICT OK %s %s %s :: %s" % (variation, sha, os.path.basename(patch), subject))
