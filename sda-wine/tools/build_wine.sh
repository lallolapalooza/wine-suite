#!/bin/bash
# Build the patched Wine tree.  Memory-aware parallelism so the build can never OOM the host
# while the win11 VM holds several GB.
#
#   tools/build_wine.sh [jobs]      # jobs optional; default derived from MemAvailable
#
# Layout (all inside the project):
#   sources/wine/wine-11.18   patched source (series + local)
#   wine/wine-11.18           build tree (out-of-tree copy)
#   wine-install/             make install prefix
#   state/tmp                 disk-backed TMPDIR (never tmpfs)
#
# All output is appended directly to logs/build.log so the log is live (no tee block-buffering).
set -euo pipefail

SD=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$SD/sources/wine/wine-11.18
BUILD=$SD/wine/wine-11.18
INSTALL=$SD/wine-install
LOG=$SD/logs/build.log

mkdir -p "$SD/wine" "$SD/state/tmp" "$SD/logs" "$INSTALL"
export TMPDIR=$SD/state/tmp

# ---- job count from available RAM: ~800 MB reserve per compile job, leave 2 GB headroom.
avail_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
avail_mb=$(( avail_kb / 1024 ))
jobs=${1:-$(( (avail_mb - 2048) / 800 ))}
[ "$jobs" -gt "$(nproc)" ] && jobs=$(nproc)
[ "$jobs" -lt 2 ] && jobs=2

{
  echo "== build_wine: avail=${avail_mb}MB jobs=${jobs} src=$SRC build=$BUILD install=$INSTALL"
  echo "== start $(date -Is)"
} >>"$LOG"

# ---- stage the source into the build tree (a fresh copy keeps the patched source pristine).
if [ ! -f "$BUILD/configure" ]; then
  echo "-- staging source -> $BUILD" >>"$LOG"
  rm -rf "$BUILD"
  mkdir -p "$(dirname "$BUILD")"
  cp -a "$SRC" "$BUILD"
fi

cd "$BUILD"

# ---- i386 (32-bit PE installer) + x86_64 (the app itself) in one build.
if [ ! -f Makefile ]; then
  echo "-- configure $(date -Is)" >>"$LOG"
  ./configure --enable-archs=i386,x86_64 --prefix="$INSTALL" >>"$LOG" 2>&1
fi

echo "-- make -j$jobs  (start $(date -Is))" >>"$LOG"
/usr/bin/time -v make -j"$jobs" >>"$LOG" 2>&1
echo "-- make finished rc=$? ($(date -Is))" >>"$LOG"

echo "-- make install $(date -Is)" >>"$LOG"
make install >>"$LOG" 2>&1
echo "-- install done ($(date -Is))" >>"$LOG"
"$INSTALL/bin/wine" --version >>"$LOG" 2>&1
echo "BUILD-OK" >>"$LOG"
