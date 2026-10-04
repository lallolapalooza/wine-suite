#!/bin/bash
# OCR a screenshot so a no-vision reader can see what is on screen.
# usage: tools/host/ocr.sh <image> [--psm N] [--lang L]
set -u
IMG=${1:?usage: ocr.sh <image>}
shift
tesseract "$IMG" stdout "$@" 2>/dev/null
