#!/bin/bash
# Make SDA render its text under Wine, reproducibly.
#
# Why: JavaFX's default prism pipeline on Windows is D3D (`prism_d3d.dll` -> Wine's d3d9), and
# `es2` (host GL) fails the same way: SDA's login panel and its red accent draw correctly but no
# glyphs appear — the "Sign in" button renders as a filled block.  The CPU pipelines rasterise the
# same glyphs correctly, and `j2d` is pixel-accurate against the Windows reference (OCR reads
# "Sign in" / "Remember me"; 247 unique colours vs 44 for the broken pipelines).
# This is WineHQ bug 37048 ("Apps using JavaFX fail to show the GUI"); its comment-5 workaround is
# exactly `-Dprism.order=j2d -Dsun.java2d.d3d=false`.
#
# Where the option goes: measured, the jpackage launcher reads `[JVMOptions]` (the app's own
# `-Dlogging.file.name` and `-Daria2c.tool` demonstrably take effect) but NOT `[JVMUserOptions]`
# (writing the same option there changed nothing).  So this script edits `[JVMOptions]`.
#
#   tools/apply_jvm_options.sh                                  # default j2d workaround
#   tools/apply_jvm_options.sh -Dprism.order=sw                 # a different pipeline
#   tools/apply_jvm_options.sh -Dprism.order=j2d -Dprism.verbose=true
#   tools/apply_jvm_options.sh --revert
#
# Idempotent: previous prism/sun.java2d overrides are replaced, not appended.
# Note: an SDA self-update rewrites this file, so re-run this after updating the app.
set -euo pipefail
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX=${SD_PREFIX:-$SD/state/prefix}
CFG="$PREFIX/drive_c/Program Files (x86)/Steinberg/Download Assistant/app/Steinberg Download Assistant.cfg"
[ -f "$CFG" ] || { echo "no app cfg at $CFG (install SDA into the prefix first)"; exit 1; }

REVERT=0
if [ "${1:-}" = "--revert" ]; then REVERT=1; shift; fi
if [ "$REVERT" = 0 ] && [ $# -eq 0 ]; then
  set -- -Dprism.order=j2d -Dsun.java2d.d3d=false
fi

NEWOPTS=$(mktemp)
trap 'rm -f "$NEWOPTS"' EXIT
if [ "$REVERT" = 0 ]; then printf '%s\n' "$@" > "$NEWOPTS"; fi

cp -f "$CFG" "$CFG.bak"
awk -v optfile="$NEWOPTS" '
  BEGIN { injvm = 0; done = 0
          while ((getline line < optfile) > 0) if (line != "") opts[++n] = line }
  { sub(/\r$/, "") }                      # the jpackage .cfg as shipped uses CRLF
  /^\[/ {
    if (injvm && !done) { for (i = 1; i <= n; i++) print opts[i]; done = 1 }
    injvm = ($0 == "[JVMOptions]")
    print; next
  }
  # drop any earlier override from any section
  /^-Dprism\.order=/   { next }
  /^-Dsun\.java2d\./   { next }
  /^[[:space:]]*$/     { if (injvm) next; print; next }
  { print }
  END { if (injvm && !done) for (i = 1; i <= n; i++) print opts[i] }
' "$CFG.bak" > "$CFG"

echo "--- [JVMOptions] now ---"
awk '/^\[JVMOptions\]/{f=1;next} /^\[/{f=0} f&&NF' "$CFG"
