#!/bin/bash
# =============================================================================
# tools/run_wine_tests.sh — build and run a Wine test suite module against this fork
#
# usage: tools/run_wine_tests.sh <module> [test-arguments ...]
#        tools/run_wine_tests.sh dwmapi dwmapi              # dlls/dwmapi/tests/dwmapi.c
#        tools/run_wine_tests.sh dwmapi                     # the whole module
#        tools/run_wine_tests.sh --list                     # module + test flag per patch
#
# Every patch that changes Wine code must come with a test in that module's dlls/<module>/tests
# suite (wired into START_TEST); this script is how the run of that suite is reproduced.  It
# builds out of the build tree, runs under the fork's own build (wine-install/bin/wine) in a
# scratch prefix (never the Solid Edge prefix), and logs to $SE_LOGS/tests/<module>[_<args>].log.
# Needs an X display (the suites create windows): DISP=:2 by default.
# =============================================================================
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh" >/dev/null 2>&1

if [ "${1:-}" = "--list" ]; then
  echo "module(s) each patch touches, and whether it carries a test:"
  for p in "$ROOT"/patches/series/*.patch "$ROOT"/patches/local/*.patch; do
    [ -e "$p" ] || continue
    m=$(grep -oE '^--- a/(dlls|server|programs)/[^/]+/' "$p" 2>/dev/null | sed 's|^--- a/||; s|/$||' | sort -u | tr '\n' ' ')
    t=$(grep -cE '^(\+\+\+) [ab]/(dlls|server|programs)/[^/]+/tests/' "$p" 2>/dev/null || true); t=${t:-0}
    if [ "$t" -gt 0 ]; then flag="test yes"; else flag="test NO "; fi
    printf '  %-58s %-26s %s\n' "$(basename "$p")" "$m" "$flag"
  done
  exit 0
fi

MODULE=${1:?usage: run_wine_tests.sh <module> [test-arguments ...]}; shift || true
TREE=$WINEROOT
WINE=$WINEPREFIX_INSTALL/bin/wine
[ -d "$TREE/dlls/$MODULE/tests" ] || { echo "no dlls/$MODULE/tests in $TREE" >&2; exit 1; }
[ -x "$WINE" ] || { echo "no built wine at $WINE" >&2; exit 1; }

TAG="$MODULE${1:+_$1}"
LOG_DIR="$SE_LOGS/tests"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$TAG.log"
TEST_PREFIX=${TEST_PREFIX:-$SE_WORK/testprefix}

echo "== building dlls/$MODULE/tests"
( cd "$TREE/dlls/$MODULE/tests" && make -j"${JOBS:-4}" ) > "$LOG_DIR/_build_$TAG.log" 2>&1 || {
  tail -20 "$LOG_DIR/_build_$TAG.log" >&2; echo "build failed (log: $LOG_DIR/_build_$TAG.log)" >&2; exit 1; }

BIN=$(ls "$TREE/dlls/$MODULE/tests/x86_64-windows/${MODULE}_test.exe" 2>/dev/null | head -1)
[ -n "$BIN" ] || BIN=$(ls "$TREE/dlls/$MODULE/tests/"*_test.exe 2>/dev/null | head -1)
[ -n "$BIN" ] || { echo "no ${MODULE}_test.exe built" >&2; exit 1; }

if [ ! -s "$TEST_PREFIX/system.reg" ]; then
  echo "== creating scratch test prefix $TEST_PREFIX"
  mkdir -p "$TEST_PREFIX"
  WINEARCH=win64 WINEPREFIX="$TEST_PREFIX" DISPLAY="${DISP:-:2}" "$WINE" wineboot -u >/dev/null 2>&1
  WINEPREFIX="$TEST_PREFIX" "$WINE" wineserver -w 2>/dev/null || true
fi

echo "== running $(basename "$BIN") $* under $WINE"
{
  echo "# $(date +%F' '%H:%M:%S)  module=$MODULE  bin=$BIN  args=$*"
  echo "# wine: $("$WINE" --version 2>/dev/null)"
  WINEPREFIX="$TEST_PREFIX" DISPLAY="${DISP:-:2}" timeout "${TEST_TIMEOUT:-1800}" "$WINE" "$BIN" "$@"
  echo "# exit=$?"
} > "$LOG" 2>&1
grep -aE 'tests executed|Test failed|failures|errors' "$LOG" | tail -5
echo "log: $LOG"
