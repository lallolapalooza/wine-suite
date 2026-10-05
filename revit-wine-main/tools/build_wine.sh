#!/bin/bash
# =============================================================================
# tools/build_wine.sh — build the patched Wine fork into wine-install/
#
# The tree that gets built is NOT wine-11.18/ (the tracked, pristine source): it is
# copied to wine/wine-11.18/ (gitignored) first, so the vendored source stays clean.
#
# usage: tools/build_wine.sh [--archs LIST] [--jobs N] [--clean] [--configure-only]
#                            [--dry-run] [--force] [--no-check]
#
#   --archs LIST        --enable-archs value (default i386,x86_64: the 64-bit product
#                       plus the 32-bit PE DLLs the licensing components need)
#   --jobs N            make -j (default: $JOBS, else the core count)
#   --clean             re-run configure on the existing tree, then rebuild
#   --configure-only    stop after configure
#   --dry-run           print the commands, change nothing
#   --force             build even if tools/check_prereqs.sh reports a blocking gap
#   --no-check          skip the prerequisite check entirely
#   --inc               incremental build only (no configure, no copy) — same as run_build.sh
#
# The reference configuration for this project was
#   ./configure --prefix=<checkout>/wine-install --enable-archs=i386,x86_64
# with clang/lld as the PE cross compiler.  Extra configure flags:
#   EXTRA_CONFIGURE="--disable-tests" tools/build_wine.sh      (skips the test suite)
#
# Produces wine-install/bin/wine and wine-install/share/wine/fonts/tahoma.ttf, both of
# which the later scripts need.  Logs: logs/build_configure.log, logs/build.log
# =============================================================================
set -eu

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

SRC=$ROOT/wine-11.18
TREE=$WINEROOT
DEST=$WINEPREFIX_INSTALL
ARCHS="i386,x86_64"
JOBS=${JOBS:-}
DO_CLEAN=0
CONFIGURE_ONLY=0
DRY_RUN=0
FORCE=0
NO_CHECK=0
INC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --archs)          ARCHS="$2"; shift 2 ;;
    --jobs|-j)        JOBS="$2"; shift 2 ;;
    --clean)          DO_CLEAN=1; shift ;;
    --configure-only) CONFIGURE_ONLY=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --force)          FORCE=1; shift ;;
    --no-check)       NO_CHECK=1; shift ;;
    --inc)            INC=1; shift ;;
    -h|--help)        sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$JOBS" ] || JOBS=$(nproc 2>/dev/null || echo 4)
[ "$DRY_RUN" = 1 ] || mkdir -p "$ROOT/logs"

say() { printf '+ %s\n' "$*"; }

# ------------------------------------------------------- 0. prerequisites ---
if [ "$NO_CHECK" = 0 ] && [ -x "$ROOT/tools/check_prereqs.sh" ]; then
  printf 'running tools/check_prereqs.sh\n'
  if ! "$ROOT/tools/check_prereqs.sh"; then
    if [ "$FORCE" = 1 ] || [ "$INC" = 1 ] || [ "$DRY_RUN" = 1 ]; then
      printf 'tools/check_prereqs.sh reported blocking gaps; continuing anyway\n' >&2
    else
      printf '\nBlocking prerequisite(s) missing - fix the [MISSING] lines above, or pass --force.\n' >&2
      exit 1
    fi
  fi
fi

if [ ! -f "$SRC/configure" ]; then
  echo "no $SRC/configure: the patched Wine source tree is missing" >&2
  exit 1
fi

# ------------------------------------------------------------- 1. tree -----
if [ ! -d "$TREE" ]; then
  if [ "$INC" = 1 ]; then
    echo "--inc requires an existing build tree at $TREE" >&2
    exit 1
  fi
  printf 'build tree: %s (copying %s)\n' "$TREE" "$SRC"
  say mkdir -p "$(dirname "$TREE")"
  say cp -a "$SRC" "$TREE"
  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$(dirname "$TREE")"
    cp -a "$SRC" "$TREE"
  fi
else
  printf 'build tree: %s (reused)\n' "$TREE"
fi

# -------------------------------------------------------- 2. configure -----
NEED_CONFIGURE=0
if [ "$INC" = 0 ] && { [ ! -f "$TREE/Makefile" ] || [ "$DO_CLEAN" = 1 ]; }; then
  NEED_CONFIGURE=1
fi

if [ "$NEED_CONFIGURE" = 1 ]; then
  CONFIGURE_ARGS=(./configure --prefix="$DEST" --enable-archs="$ARCHS")
  # shellcheck disable=SC2206  # intentional word splitting: EXTRA_CONFIGURE is a flag list
  [ -n "${EXTRA_CONFIGURE:-}" ] && CONFIGURE_ARGS+=($EXTRA_CONFIGURE)
  printf '\n== configure\n'
  say "(cd $TREE && ${CONFIGURE_ARGS[*]})"
  if [ "$DRY_RUN" = 0 ]; then
    ( cd "$TREE" && "${CONFIGURE_ARGS[@]}" ) > "$ROOT/logs/build_configure.log" 2>&1 || {
      tail -30 "$ROOT/logs/build_configure.log" >&2
      echo "configure failed (logs/build_configure.log)" >&2
      exit 1
    }
    tail -5 "$ROOT/logs/build_configure.log"
    printf 'configure done; full output: logs/build_configure.log\n'
  fi
elif [ "$INC" = 1 ]; then
  printf '\n== configure skipped (--inc)\n'
else
  printf '\n== configure skipped (%s/Makefile exists; --clean re-runs it)\n' "$TREE"
fi

if [ "$CONFIGURE_ONLY" = 1 ]; then
  printf 'stopping after configure (--configure-only)\n'
  exit 0
fi

# ------------------------------------------------------------- 3. make -----
printf '\n== make -j%s\n' "$JOBS"
say "make -C $TREE -j$JOBS"
if [ "$DRY_RUN" = 0 ]; then
  # streamed and kept: a build of both architectures is long enough that losing the output
  # would cost another run
  ( cd "$TREE" && make -j"$JOBS" ) 2>&1 | tee "$ROOT/logs/build.log"
  printf 'build finished; log: logs/build.log\n'
fi

# ------------------------------------------------------- 4. make install ---
printf '\n== make install (into %s)\n' "$DEST"
say "make -C $TREE install"
if [ "$DRY_RUN" = 0 ]; then
  ( cd "$TREE" && make install ) 2>&1 | tee -a "$ROOT/logs/build.log"
fi

if [ "$DRY_RUN" = 1 ]; then
  printf '\ndry run: nothing was copied, configured, built or installed\n'
  exit 0
fi

# ------------------------------------------------------- 5. sanity ---------
printf '\n== result\n'
fail=0
if [ -x "$DEST/bin/wine" ]; then
  printf '  [ ok ]      %s --version -> %s\n' "$DEST/bin/wine" "$("$DEST/bin/wine" --version 2>/dev/null)"
else
  printf '  [MISSING]   %s/bin/wine was not installed\n' "$DEST"; fail=1
fi
if [ -f "$DEST/share/wine/fonts/tahoma.ttf" ]; then
  printf '  [ ok ]      %s/share/wine/fonts/tahoma.ttf (tools/make_wine_fonts.py needs it)\n' "$DEST"
else
  printf '  [warn]      %s/share/wine/fonts/tahoma.ttf absent: the Arial/Microsoft Sans Serif\n' "$DEST"
  printf '              substitutes cannot be built and the WPF UI will not lay out\n'
fi
printf '\nnext: tools/install_revit_prefix.sh $REVIT_WORK/prefix\n'
exit "$fail"
