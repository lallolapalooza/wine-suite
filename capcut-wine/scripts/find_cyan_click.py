#!/usr/bin/env python3
"""Find the CapCut accent-colour (cyan) button in a screenshot.

usage: find_cyan_click.py <png>
Prints "<x> <y> <pixels>" for the centroid of the cyan pixels, or nothing if the
image has fewer than 80 cyan pixels.  Used by cc_run.sh's CC_AUTOCLICK to press
"Agree and continue" / "Confirm" dialogs that otherwise block the app.

No third-party deps: the PNG is converted to a raw PPM by ImageMagick and parsed here.
"""
import subprocess
import sys

path = sys.argv[1]
raw = subprocess.run(["convert", path, "-depth", "8", "ppm:-"],
                     capture_output=True, check=True).stdout

# parse P6 header: "P6\n<w> <h>\n<max>\n" (four whitespace-separated fields)
pos = 0
fields = []
while len(fields) < 4:
    while raw[pos:pos + 1].isspace():
        pos += 1
    if raw[pos:pos + 1] == b'#':
        while raw[pos:pos + 1] not in (b'\n', b''):
            pos += 1
        continue
    start = pos
    while not raw[pos:pos + 1].isspace():
        pos += 1
    fields.append(raw[start:pos])
w, h = int(fields[1]), int(fields[2])
pos += 1  # exactly one whitespace byte after maxval
px = raw[pos:pos + w * h * 3]

def cyan(r, g, b):
    return r < 130 and g > 150 and b > 150 and abs(g - b) < 70


# The button is the widest *solid* cyan run on any scanline; the cyan hyperlink
# text is much thinner.  Find the best run...
best = (0, 0, 0)          # run length, y, x_start
for y in range(h):
    row = y * w
    run = 0
    start = 0
    for x in range(w):
        i = (row + x) * 3
        if cyan(px[i], px[i + 1], px[i + 2]):
            if run == 0:
                start = x
            run += 1
            if run > best[0]:
                best = (run, y, start)
        else:
            run = 0

if best[0] < 80:
    sys.exit(0)

run, y, xs = best
cx = xs + run // 2
# ...then walk up/down at cx to get the button's vertical centre.
top = y
while top > 0 and cyan(*px[((top - 1) * w + cx) * 3:((top - 1) * w + cx) * 3 + 3]):
    top -= 1
bot = y
while bot < h - 1 and cyan(*px[((bot + 1) * w + cx) * 3:((bot + 1) * w + cx) * 3 + 3]):
    bot += 1
print(cx, (top + bot) // 2, run)
