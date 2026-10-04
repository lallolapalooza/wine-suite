#!/bin/bash
# =============================================================================
# tools/build_wine.sh — configure, build and install the patched Wine fork
#
# The recipe is the one from the Wine wiki, "Building Wine" -> "New WoW64 Build"
# (https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine):
#
#     ./configure --enable-archs=i386,x86_64
#     make -j`nproc`
#
# --enable-archs=i386,x86_64 is the "new WoW64" build: it runs 32-bit and 64-bit Windows
# binaries on 64-bit Linux with no 32-bit Linux libraries, all 32-bit code being PE built by
# clang/lld.  `make install` into wine-install/ then gives wine-install/bin/wine.
#
# usage: tools/build_wine.sh [--jobs N] [--clean] [--configure-only] [--inc] [--dry-run]
#                            [--disable-tests] [--force]
#
#   --jobs N           make -j (default: $JOBS, else 8 — see the memory guard below)
#   --clean            re-run configure, then rebuild
#   --configure-only   stop after configure
#   --inc              incremental: no configure, no rebuild of the tree copy
#   --dry-run          print the commands, change nothing
#   --disable-tests    skip Wine's own test suites (much faster; the fork's patches ship tests,
#                      so only use this when you do not intend to run them)
#   --force            build even if the memory guard says there is not enough free RAM
#
# Memory guard: each parallel compile of Wine can take ~500 MB-1 GB at peak, and this host
# also runs an 8 GiB Windows guest.  The script refuses to start with less than MIN_FREE_MB
# (default 5000) available and caps -j at (available MiB / 1000).
#
# Logs: logs/build_configure.log, logs/build.log
# =============================================================================
set -eu

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

SRC=$ROOT/wine-11.18            # pristine + patches (the tracked source)
TREE=$WINEROOT                  # the tree that gets built
DEST=$WINEPREFIX_INSTALL
ARCHS=${ARCHS:-i386,x86_64}
JOBS=""
DO_CLEAN=0
CONFIGURE_ONLY=0
DRY_RUN=0
INC=0
FORCE=0
EXTRA_CONFIGURE=${EXTRA_CONFIGURE:-}
MIN_FREE_MB=${MIN_FREE_MB:-5000}

while [ $# -gt 0 ]; do
  case "$1" in
    --jobs|-j)        JOBS="$2"; shift 2 ;;
    --clean)          DO_CLEAN=1; shift ;;
    --configure-only) CONFIGURE_ONLY=1; shift ;;
    --inc)            INC=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --disable-tests)  EXTRA_CONFIGURE="$EXTRA_CONFIGURE --disable-tests"; shift ;;
    --force)          FORCE=1; shift ;;
    -h|--help)        sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '+ %s\n' "$*"; }

# ------------------------------------------------------ 0. memory guard -----
avail_mb=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
printf 'free memory: %s MiB available (guard %s MiB)\n' "$avail_mb" "$MIN_FREE_MB"
if [ "$avail_mb" -lt "$MIN_FREE_MB" ] && [ "$FORCE" = 0 ] && [ "$DRY_RUN" = 0 ] && [ "$CONFIGURE_ONLY" = 0 ]; then
  printf 'refusing to build: only %s MiB available.  Free memory (stop the %s guest?) or pass --force.\n' \
      "$avail_mb" "win11" >&2
  exit 1
fi
if [ -z "$JOBS" ]; then
  JOBS=${JOBS_ENV:-}
fi
if [ -z "$JOBS" ]; then
  JOBS=$(( avail_mb / 1000 ))
  [ "$JOBS" -gt 8 ] && JOBS=8
  [ "$JOBS" -lt 1 ] && JOBS=1
fi
printf 'make -j%s\n' "$JOBS"

mkdir -p "$ROOT/logs"

# ------------------------------------------------------------- 1. tree ------
if [ ! -f "$SRC/configure" ]; then
  echo "no $SRC/configure — the patched source tree is missing (tools/apply_patches.sh)" >&2
  exit 1
fi
if [ ! -d "$TREE" ]; then
  printf 'build tree: %s (copying %s)\n' "$TREE" "$SRC"
  if [ "$DRY_RUN" = 0 ]; then mkdir -p "$(dirname "$TREE")"; cp -a "$SRC" "$TREE"; fi
else
  printf 'build tree: %s (reused)\n' "$TREE"
fi

# -------------------------------------------------------- 2. configure -----
NEED_CONFIGURE=0
if [ "$INC" = 0 ] && { [ ! -f "$TREE/Makefile" ] || [ "$DO_CLEAN" = 1 ]; }; then NEED_CONFIGURE=1; fi
if [ "$NEED_CONFIGURE" = 1 ]; then
  # shellcheck disable=SC2206
  CONFIGURE_ARGS=(./configure --prefix="$DEST" --enable-archs="$ARCHS")
  [ -n "$EXTRA_CONFIGURE" ] && CONFIGURE_ARGS+=($EXTRA_CONFIGURE)
  printf '\n== configure\n'
  say "(cd $TREE && ${CONFIGURE_ARGS[*]})"
  if [ "$DRY_RUN" = 0 ]; then
    ( cd "$TREE" && "${CONFIGURE_ARGS[@]}" ) > "$ROOT/logs/build_configure.log" 2>&1 || {
      tail -30 "$ROOT/logs/build_configure.log" >&2
      echo "configure failed (logs/build_configure.log)" >&2; exit 1; }
    tail -4 "$ROOT/logs/build_configure.log"
  fi
else
  printf '\n== configure skipped\n'
fi
[ "$CONFIGURE_ONLY" = 1 ] && { printf 'stopping after configure\n'; exit 0; }

# ------------------------------------------------------------- 3. make -----
printf '\n== make -j%s\n' "$JOBS"
if [ "$DRY_RUN" = 0 ]; then
  ( cd "$TREE" && make -j"$JOBS" ) 2>&1 | tee "$ROOT/logs/build.log"
fi

printf '\n== make install -> %s\n' "$DEST"
if [ "$DRY_RUN" = 0 ]; then
  ( cd "$TREE" && make install ) 2>&1 | tee -a "$ROOT/logs/build.log"
fi
[ "$DRY_RUN" = 1 ] && { printf '\ndry run: nothing done\n'; exit 0; }

# ---------------------------------------------------------- 4. sanity ------
printf '\n== result\n'
fail=0
if [ -x "$DEST/bin/wine" ]; then
  printf '  [ ok ]      %s --version -> %s\n' "$DEST/bin/wine" "$("$DEST/bin/wine" --version 2>/dev/null)"
else
  printf '  [MISSING]   %s/bin/wine\n' "$DEST"; fail=1
fi
[ -f "$DEST/share/wine/fonts/tahoma.ttf" ] && printf '  [ ok ]      tahoma.ttf (tools/make_wine_fonts.py needs it)\n' \
  || printf '  [warn]      no share/wine/fonts/tahoma.ttf\n'
[ -x "$DEST/bin/msidb" ] && printf '  [ ok ]      msidb\n'
exit "$fail"
