#!/bin/bash
# Screenshot the guest console and OCR it.  usage: vmshot.sh <out.png> [--no-ocr]
set -u
OUT=${1:-/tmp/vmshot.png}
DOMAIN=${VM_DOMAIN:-win11}
TMP=$(mktemp /tmp/vmshot.XXXX.ppm)
if ! virsh screenshot "$DOMAIN" "$TMP" >/dev/null 2>&1; then echo "screenshot failed"; rm -f "$TMP"; exit 1; fi
convert "$TMP" "$OUT" 2>/dev/null || cp "$TMP" "$OUT"
rm -f "$TMP"
echo "saved $OUT"
if [ "${2:-}" != "--no-ocr" ]; then
  tesseract "$OUT" stdout 2>/dev/null | sed '/^\s*$/d'
fi
