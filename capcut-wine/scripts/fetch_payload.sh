#!/bin/bash
# Fetch the CapCut PC payload directly (no Windows guest needed).
#
# The 2.9 MB stub installer fetches this itself; the URL was recovered from a user-mode minidump of the
# running downloader on the Windows reference guest (its own auto_updater.cc log line), and verified
# byte-for-byte against the payload the stub downloaded here under Wine:
#   size  559,656,336   sha256 e3755d1798fdea572e4a781e5b39f759b3f2c32cc5d590e71006df7b6f00664f
#
# This is the "JYPacket" app package (Bytedance.CapCut / CapCut Installer Application v1.0 / 9.5.0.4050).
# Installing it is what puts CapCut into the prefix.
#
# usage: fetch_payload.sh [outdir]
set -eu
CCWS=/home/asdf/projects/capcut-wine
OUT=${1:-$CCWS/work/payload}
URL="https://sf16-web-tos-buz.capcutstatic.com/obj/capcut-web-buz-sg/packages/CapCut_9_5_0_4050_capcutpc_0_creatortool.exe"
EXPECT=e3755d1798fdea572e4a781e5b39f759b3f2c32cc5d590e71006df7b6f00664f
mkdir -p "$OUT"
F="$OUT/app_package.exe"

if [ -f "$F" ] && [ "$(sha256sum "$F" | cut -d' ' -f1)" = "$EXPECT" ]; then
  echo "already present and correct: $F"; exit 0
fi

echo "downloading $URL"
curl -fL --retry 3 -o "$F.part" "$URL"
got=$(sha256sum "$F.part" | cut -d' ' -f1)
if [ "$got" != "$EXPECT" ]; then
  echo "HASH MISMATCH: expected $EXPECT got $got" >&2
  exit 1
fi
mv "$F.part" "$F"
sha256sum "$F" > "$OUT/app_package.sha256"
echo "ok: $F ($(stat -c %s "$F") bytes)"
