#!/bin/bash
# Guest screenshot + OCR in one step (no vision required).
# usage: tools/vm/vmshot.sh <out.png> [--psm N]
set -u
DOMAIN=${VM_DOMAIN:-win11}
OUT=${1:?usage: vmshot.sh <out.png> [--psm N]}
shift
TMP=$(mktemp /tmp/vmshot.XXXX.ppm)
if ! virsh screenshot "$DOMAIN" "$TMP" >/dev/null 2>&1; then echo "screenshot failed"; exit 1; fi
if command -v convert >/dev/null 2>&1; then convert "$TMP" "$OUT" 2>/dev/null || cp "$TMP" "$OUT"; else cp "$TMP" "$OUT"; fi
rm -f "$TMP"
MEAN=$(identify -format '%[fx:mean]' "$OUT" 2>/dev/null)
echo "== $OUT  mean=$MEAN =="
tesseract "$OUT" stdout "$@" 2>/dev/null
