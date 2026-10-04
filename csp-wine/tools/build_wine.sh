#!/bin/bash
# Build the patched Wine tree.  Memory-aware parallelism so the build can never OOM the host
# while the win11 VM holds ~8 GB.
#
#   tools/build_wine.sh [jobs]      # jobs optional; default derived from MemAvailable
#
# Layout (all inside the project):
#   sources/wine/wine-11.18   patched source (series + local)
#   wine/wine-11.18           build tree (out-of-tree copy)
#   wine-install/             make install prefix
#   state/tmp                 disk-backed TMPDIR (never tmpfs)
set -euo pipefail

CW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$CW/sources/wine/wine-11.18
BUILD=$CW/wine/wine-11.18
INSTALL=$CW/wine-install
LOG=$CW/logs/build.log

mkdir -p "$CW/wine" "$CW/state/tmp" "$CW/logs" "$INSTALL"
export TMPDIR=$CW/state/tmp

# ---- job count from available RAM: ~800 MB reserve per compile job, leave 2 GB headroom.
avail_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
avail_mb=$(( avail_kb / 1024 ))
jobs=${1:-$(( (avail_mb - 2048) / 800 ))}
[ "$jobs" -gt "$(nproc)" ] && jobs=$(nproc)
[ "$jobs" -lt 2 ] && jobs=2

echo "== build_wine: avail=${avail_mb}MB jobs=${jobs} src=$SRC build=$BUILD install=$INSTALL" | tee "$LOG"

# ---- stage the source into the build tree (fresh copy keeps patches pristine).
if [ ! -f "$BUILD/configure" ]; then
  echo "-- staging source -> $BUILD" | tee -a "$LOG"
  rm -rf "$BUILD"
  mkdir -p "$(dirname "$BUILD")"
  cp -a "$SRC" "$BUILD"
fi

cd "$BUILD"

# ---- freetype etc. are system-provided; x86_64+i386 covers the 32-bit installer and the 64-bit app.
if [ ! -f Makefile ]; then
  echo "-- configure" | tee -a "$LOG"
  ./configure --enable-archs=i386,x86_64 --prefix="$INSTALL" 2>&1 | tee -a "$LOG"
fi

echo "-- make -j$jobs  (start $(date -Is))" | tee -a "$LOG"
/usr/bin/time -v make -j"$jobs" 2>&1 | tee -a "$LOG" | grep -E "Maximum resident|Elapsed \(wall|Error|error:" || true
echo "-- make finished rc=${PIPESTATUS[0]} ($(date -Is))" | tee -a "$LOG"

echo "-- make install" | tee -a "$LOG"
make install 2>&1 | tee -a "$LOG" | tail -5
echo "-- install done ($(date -Is))" | tee -a "$LOG"
"$INSTALL/bin/wine" --version | tee -a "$LOG"
echo "BUILD-OK" | tee -a "$LOG"
