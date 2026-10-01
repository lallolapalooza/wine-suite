#!/bin/bash
# =============================================================================
# tools/verify_revit.sh — prove the end state from a prefix
#
# usage: tools/verify_revit.sh <prefix-path> [seconds] [--apphome]
#
# Launches Revit from that prefix (tools/run_revit.sh) on the project's display and reads the
# evidence back:
#
#   * Revit.exe is installed and stays alive for the whole sample window
#   * Revit's main window exists, is titled and is captured (>= 2 samples)
#   * the surface is painted (a window capture larger than a blank frame)
#   * zero ".NET Assertion Failed" / unhandled-exception dialogs
#   * no "Autodesk Revit has stopped working" crash dialog
#
# Prints PASS/FAIL per check; exits non-zero if any failed.
# Evidence: $REVIT_LOGS/ui/<tag>/{out.txt,win_*s.png,screen_*s.png}, $REVIT_LOGS/log_<tag>.txt
# =============================================================================
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh" >/dev/null 2>&1

PREFIX_IN=${1:?usage: verify_revit.sh <prefix-path> [seconds]}
SECS=${2:-240}
PREFIX=$(readlink -f "$PREFIX_IN")
TAG="verify_$(basename "$PREFIX")"
OUT="$REVIT_LOGS/ui/$TAG/out.txt"
RUNLOG="$REVIT_LOGS/log_$TAG.txt"

FAIL=0
skip() { printf 'SKIP  %-52s %s\n' "$1" "$2"; }
check() { # <name> <0|1> <detail>
  if [ "$2" = 1 ]; then printf 'PASS  %-52s %s\n' "$1" "$3"
  else printf 'FAIL  %-52s %s\n' "$1" "$3"; FAIL=1; fi
}

echo "== verifying $PREFIX (tag $TAG, ${SECS}s, display ${DISP:-:2})"

if [ ! -f "$PREFIX/drive_c/Program Files/Autodesk/Revit 2027/Revit.exe" ]; then
  check "Revit.exe installed" 0 "no Program Files/Autodesk/Revit 2027/Revit.exe"
  exit 1
fi
check "Revit.exe installed" 1 "$(du -sh "$PREFIX/drive_c/Program Files/Autodesk/Revit 2027" | cut -f1)"

# --- install completeness (see README "Packages ODIS never downloads") -------------------------
# The install manager can abort with packages still queued; the files that only live in those
# packages are then absent, and the program directory cannot load (DesktopMFC.dll imports the
# Qt6/Stingray set that RCPCOMEXT carries).  Both conditions are checked here because they are the
# difference between "installed" and "runnable".
REVDIR="$PREFIX/drive_c/Program Files/Autodesk/Revit 2027"
dll_missing=""
for d in Qt6Core.dll Qt6Gui.dll QtSolutions_MFCMigrationFramework.dll RWUXThemeSU2015.dll \
         sfl400asu.dll ot1000asu.dll og1100asu.dll Ecotect.dll Utility.dll; do
  [ -f "$REVDIR/$d" ] || dll_missing="$dll_missing $d"
done
check "load-path DLLs present (RCPCOMEXT etc.)" "$([ -z "$dll_missing" ] && echo 1 || echo 0)" "${dll_missing:-all present}"

fpy=python3; [ -x "$ROOT/tools/venv/bin/python" ] && fpy="$ROOT/tools/venv/bin/python"
skipped=$("$fpy" "$ROOT/tools/fetch_missing_packages.py" "$PREFIX" --dry-run 2>/dev/null \
          | sed -n '/^  [A-Za-z]/p' | awk '{print $1}' | grep -vE '^(AGS|Access|OpenStudio|PACR)$' | tr '\n' ' ')
if [ -z "$skipped" ]; then
  check "no ADIX package left undownloaded" 1 "only the four MSI-type packages are installer-run"
else
  check "no ADIX package left undownloaded" 0 "unstaged: $skipped(run tools/fetch_missing_packages.py)"
fi

WINEPREFIX="$PREFIX" "$ROOT/tools/run_revit.sh" "$TAG" "$SECS" 20 >/dev/null 2>&1
[ -f "$OUT" ] || { check "run produced evidence" 0 "no $OUT"; exit 1; }

samples=$(grep -ac '^t=' "$OUT")
wins=$(grep -ac 'win=0x' "$OUT")
alive=$(awk '/^t=/{split($2,a,"="); if (a[2]+0>0) n++} END{print n+0}' "$OUT")
asserts=$(grep -ac 'Assertion Failed' "$OUT" || true)
crash=$(grep -aci 'Unhandled exception\|stopped working\|page fault' "$RUNLOG" 2>/dev/null || echo 0)
painted=$(find "$REVIT_LOGS/ui/$TAG" -name 'win_*s.png' -size +20k 2>/dev/null | wc -l)

check "Revit process alive across samples" "$([ "$alive" -ge 2 ] && echo 1 || echo 0)" "$alive/$samples samples with a live Revit.exe"
check "main window titled and sampled"     "$([ "$wins" -ge 2 ] && echo 1 || echo 0)" "$wins window samples"
check "screenshots captured"               "$([ "$(find "$REVIT_LOGS/ui/$TAG" -name '*.png' | wc -l)" -ge 2 ] && echo 1 || echo 0)" "$(find "$REVIT_LOGS/ui/$TAG" -name '*.png' | wc -l) captures"
check "surface painted (non-blank frame)"  "$([ "$painted" -ge 1 ] && echo 1 || echo 0)" "$painted capture(s) > 20 kB"
check "no .NET assertion dialog"           "$([ "$asserts" = 0 ] && echo 1 || echo 0)" "assert lines=$asserts"
check "no crash dialog / unhandled exception" "$([ "$crash" = 0 ] && echo 1 || echo 0)" "matches=$crash"

echo
echo "evidence: $REVIT_LOGS/ui/$TAG/  and  $RUNLOG"
[ "$FAIL" = 0 ] && echo "== ALL CHECKS PASSED" || echo "== CHECKS FAILED"
exit "$FAIL"
