#!/bin/bash
# =============================================================================
# tools/verify_fresh_prefix.sh — prove the end state from a given prefix
# =============================================================================
#
# usage: tools/verify_fresh_prefix.sh <prefix-path> [seconds] [--apphome]
#
# Launches acad.exe from <prefix-path> (never the shared reference prefix unless you ask for
# it) on the project's VNC display and then reads the evidence back:
#
#   * acad's UI renders: window titles + screenshots captured by ui_plug.sh
#   * zero ".NET Assertion Failed" dialogs
#   * no licence-error dialog ("License Error" / "License manager is not functioning")
#   * the licensing agent's WebView2 reached /ui/v2/lgs ("Let's Get Started")
#   * the AppHome webview loaded (acad's own WebView2 history; --apphome starts acad without a
#     drawing, which is the only way acad creates that webview)
#
# Prints a PASS/FAIL line per check and exits non-zero if any check failed.
# Evidence: logs/ui/<tag>/{out.txt,win_*s.png,screen_*s.png} and log_<tag>.txt
# =============================================================================
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX_IN="${1:?usage: verify_fresh_prefix.sh <prefix-path> [seconds] [--apphome]}"
SECS="${2:-200}"
APPHOME=0
for a in "$@"; do [ "$a" = "--apphome" ] && APPHOME=1; done
PREFIX=$(readlink -f "$PREFIX_IN")
TAG="verify_$(basename "$PREFIX")$( [ "$APPHOME" = 1 ] && echo _apphome )"
DISPX=${DISP:-:2}                     # the display ui_plug.sh will run acad on
DWG=""
[ "$APPHOME" = 0 ] && DWG='C:\probe\titleblock.dwg'   # a drawing, if a fixture is available

FAIL=0
skip() { printf 'SKIP  %-52s %s\n' "$1" "$2"; }
check() {   # <name> <0|1 pass> <detail>
  if [ "$2" = 1 ]; then printf 'PASS  %-52s %s\n' "$1" "$3"
  else printf 'FAIL  %-52s %s\n' "$1" "$3"; FAIL=1; fi
}

echo "== verifying $PREFIX (tag $TAG, ${SECS}s, display $DISPX, dwg='${DWG:-none}')"
[ -f "$PREFIX/drive_c/Program Files/Autodesk/AutoCAD 2027/acad.exe" ] || { echo "no acad.exe in $PREFIX"; exit 2; }

# the drawing acad is launched with, so the frame shows a real drawing.  The fixture is not
# kept in the tree (it is Autodesk media); point VERIFY_DWG at one, or the run goes ahead
# without a drawing and the drawing-dependent checks are reported as skipped.
FIXTURE="${VERIFY_DWG:-$ROOT/tools/refdata/verify/titleblock.dwg}"
PROBE_DIR="$PREFIX/drive_c/probe"
if [ -n "$DWG" ]; then
  mkdir -p "$PROBE_DIR"
  [ -f "$PROBE_DIR/titleblock.dwg" ] || install -m 644 "$FIXTURE" "$PROBE_DIR/titleblock.dwg" 2>/dev/null
  if [ ! -f "$PROBE_DIR/titleblock.dwg" ]; then
    echo "note: no drawing fixture at $FIXTURE (set VERIFY_DWG); running without a drawing"
    DWG=""
  fi
fi
rm -f "$PREFIX/drive_c/licrec.txt"     # a debug hook from the project this came from; absent here

# Clear acad's "the last session crashed" marker, so the run starts clean: a killed previous
# session leaves HKCU\...\Profiles\<<Unnamed Profile>>\Drawing Recovery\{,Unresolved} behind,
# which pops the Drawing Recovery palette over the UI.  This is run state, not install state.
PROFKEY='HKCU\Software\Autodesk\AutoCAD\R26.0\ACAD-A101:409\Profiles\<<Unnamed Profile>>\Drawing Recovery'
WINEPREFIX="$PREFIX" "$ROOT/wine-install/bin/wine" reg delete "$PROFKEY" /f >/dev/null 2>&1
WINEPREFIX="$PREFIX" "$ROOT/wine-install/bin/wine" reg delete "$PROFKEY\\Unresolved" /f >/dev/null 2>&1

WINEPREFIX="$PREFIX" DISP="$DISPX" bash "$ROOT/ui_plug.sh" "$TAG" "$DWG" "$SECS" 20 >/dev/null 2>&1
OUT="$ROOT/logs/ui/$TAG/out.txt"
ACADLOG="$ROOT/log_$TAG.txt"

# --- licence-failure record -------------------------------------------------
# In the project this came from, a debug-only user32!LoadStringW hook (patch 0011, not part
# of this repository) wrote acad's licence-failure reason to C:\licrec.txt.  Without it the
# file can never appear, so its absence is not evidence: report SKIP rather than a pass.
LICREC="$PREFIX/drive_c/licrec.txt"
if [ -s "$LICREC" ]; then
  check "no licence-failure record in C:\\licrec.txt" 0 "acad recorded: $(head -3 "$LICREC" | tr '\n' ' ')"
else
  skip "no licence-failure record in C:\\licrec.txt" "patch 0011 is not in this repo (debug-only); nothing writes the file"
fi

# --- window/dialog evidence -------------------------------------------------
# grep -c prints the count (0 included) and exits 1 on no match; capture stdout only.
cnt() { local n; n=$(grep -ac "$1" "$2" 2>/dev/null); echo "${n:-0}"; }
# ui_plug.sh writes `win=<id>` on each sample for which it found a window titled
# "Autodesk AutoCAD ..." in the X tree, so counting those samples is the title evidence.
asserts=$(cnt 'Assertion Failed' "$OUT")
licerr=$(cnt 'License Error\|License manager is not functioning' "$OUT")
acadwin=$(cnt 'win=0x' "$OUT")
[ "$asserts" = 0 ]; check "no .NET Assertion Failed dialog" "$([ "$asserts" = 0 ] && echo 1 || echo 0)" "assert lines=$asserts"
[ "$licerr" = 0 ];  check "no licence-error dialog"          "$([ "$licerr" = 0 ] && echo 1 || echo 0)" "matches=$licerr"
[ "$acadwin" -gt 0 ]; check "acad main window titled/titled+sampled" "$([ "$acadwin" -gt 0 ] && echo 1 || echo 0)" "title-matching samples=$acadwin"
shots=$(ls "$ROOT/logs/ui/$TAG"/win_*s.png 2>/dev/null | wc -l)
[ "$shots" -gt 0 ]; check "screenshots captured"             "$([ "$shots" -gt 0 ] && echo 1 || echo 0)" "$shots window captures in logs/ui/$TAG/"
# a blank/unpainted window capture compresses to a few kB; a painted AutoCAD frame is ~30 kB+
big=$(find "$ROOT/logs/ui/$TAG" -name 'win_*s.png' -size +20k 2>/dev/null | wc -l)
[ "$big" -gt 0 ]; check "acad surface painted (non-blank frame)" "$([ "$big" -gt 0 ] && echo 1 || echo 0)" "$big capture(s) > 20 kB (largest: $(find "$ROOT/logs/ui/$TAG" -name 'win_*s.png' -printf '%s\n' 2>/dev/null | sort -n | tail -1) bytes)"

# --- licensing UI evidence --------------------------------------------------
# The licence UI is the AdskLicensingAgent's own WebView2; its Chromium history is the
# authoritative record of the URL it navigated to (FINDINGS M24ae).
hist="$PREFIX/drive_c/users/$(whoami)/AppData/Local/Autodesk/AdskLicensingAgent/v1/native/EBWebView/Default/History"
lic_urls=$("$ROOT/tools/venv/bin/python" - "$hist" <<'PY' 2>/dev/null
import os, shutil, sqlite3, sys, tempfile
src = sys.argv[1]
if not os.path.exists(src): raise SystemExit
tmp = tempfile.mktemp(); shutil.copy(src, tmp)
try:
    con = sqlite3.connect(tmp)
    for (u,) in con.execute("select url from urls order by last_visit_time desc limit 40"):
        print(u)
finally:
    os.unlink(tmp)
PY
)
lgs=$(printf '%s\n' "$lic_urls" | grep -c '/ui/v2/lgs')
err=$(printf '%s\n' "$lic_urls" | grep -c '/ui/v2/error')
check "licensing UI reached /ui/v2/lgs" "$([ "$lgs" -gt 0 ] && echo 1 || echo 0)" "lgs=$lgs error-page=$err"
printf '%s\n' "$lic_urls" | grep -m1 '/ui/v2/' | sed 's/^/      last licence URL: /'

# --- AppHome evidence -------------------------------------------------------
ahist="$PREFIX/drive_c/users/$(whoami)/AppData/Local/ADPWebView/acad/32/cache_1/EBWebView/Default/History"
app_urls=$("$ROOT/tools/venv/bin/python" - "$ahist" <<'PY' 2>/dev/null
import os, shutil, sqlite3, sys, tempfile
src = sys.argv[1]
if not os.path.exists(src): raise SystemExit
tmp = tempfile.mktemp(); shutil.copy(src, tmp)
try:
    con = sqlite3.connect(tmp)
    for (u,) in con.execute("select url from urls order by last_visit_time desc limit 40"):
        print(u)
finally:
    os.unlink(tmp)
PY
)
if [ "$APPHOME" = 1 ]; then
  home=$(printf '%s\n' "$app_urls" | grep -ciE 'swclient|AppHome|autocad\.sw')
  check "AppHome webview loaded its app" "$([ "$home" -gt 0 ] && echo 1 || echo 0)" "urls=$home"
  printf '%s\n' "$app_urls" | grep -m1 -iE 'swclient|AppHome' | sed 's/^/      last AppHome URL: /'
fi

echo
echo "evidence: logs/ui/$TAG/  and  $ACADLOG"
[ "$FAIL" = 0 ] && echo "== ALL CHECKS PASSED" || echo "== SOME CHECKS FAILED"
exit "$FAIL"
