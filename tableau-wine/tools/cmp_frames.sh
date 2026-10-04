#!/bin/bash
# Side-by-side and difference metrics for a Windows-guest frame vs a Wine frame.
#   tools/cmp_frames.sh <windows.png> <wine.png> [out.png]
# Prints the raw-pixel difference (ImageMagick AE/RMSE) and writes a labelled side-by-side montage.
set -u
A=${1:?windows png}; B=${2:?wine png}; OUT=${3:-/tmp/cmp.png}
for f in "$A" "$B"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done

# normalise both to the same size so AE is meaningful
magick "$A" -resize 1280x800! -depth 8 /tmp/_cmp_a.png
magick "$B" -resize 1280x800! -depth 8 /tmp/_cmp_b.png
echo -n "AE(absolute error px): "; magick compare -metric AE /tmp/_cmp_a.png /tmp/_cmp_b.png null: 2>&1; echo
echo -n "RMSE: "; magick compare -metric RMSE /tmp/_cmp_a.png /tmp/_cmp_b.png null: 2>&1; echo
echo -n "mean abs diff: "; magick /tmp/_cmp_a.png /tmp/_cmp_b.png -compose difference -composite -format '%[fx:mean*255]' info:; echo
magick montage -label 'WINDOWS' "$A" -label 'WINE' "$B" -tile 2x1 -geometry +4+4 -background '#222' "$OUT"
identify "$OUT"
