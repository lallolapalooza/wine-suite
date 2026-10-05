#!/bin/bash
# =============================================================================
# tools/install_revit_prefix.sh — take an EMPTY Wine prefix to an installed Revit 2027
#
# usage: tools/install_revit_prefix.sh <prefix-path> [--install-only] [--force-install]
#
#   (default)        create the prefix, run the unattended Autodesk install, apply the four
#                    environment fixups a Wine prefix needs, then report the end state.
#   --install-only   stop after the install + measurement (no fixups).
#   --force-install  install even if Revit.exe is already present.
#
# Steps:
#   1. prefix          wineboot -u, win64, Windows 10
#   2. install         (cd $REVIT_MEDIA && Setup.exe -q) — the ODIS web installer
#   3. fixups          fonts, hosts, RpcSs/SamSs, WebView2 flags  (Wine-vs-Windows only)
#   4. report          Revit.exe? ODIS DB counts? package states? payload size?
#
# Media: $REVIT_MEDIA (default <checkout>/installer) needs Setup.exe + ODIS/ — the extracted
# payload of Autodesk_Revit_2027_*_setup_webinstall.exe:
#     7z x -o installer Autodesk_Revit_2027_3_ML_setup_webinstall.exe
# Do NOT pre-extract the stub's private SxS assemblies next to Setup.exe: patch 0016
# (ntdll/actctx probing privatePath) resolves them from ODIS/ as on Windows.
#
# Logs: $REVIT_LOGS/<prefix-name>/
# =============================================================================
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"
WINE=${REVIT_WINE:-$WINEPREFIX_INSTALL/bin/wine}
MEDIA=${REVIT_MEDIA:-$ROOT/installer}
DISPLAY_X=${DISP:-:2}

PREFIX_IN=""
INSTALL_ONLY=0
FORCE_INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install-only)  INSTALL_ONLY=1 ;;
    --force-install) FORCE_INSTALL=1 ;;
    -h|--help)       sed -n '2,25p' "$0"; exit 0 ;;
    -*)              echo "unknown option: $arg" >&2; exit 2 ;;
    *)               PREFIX_IN="$arg" ;;
  esac
done
[ -n "$PREFIX_IN" ] || { sed -n '2,6p' "$0" >&2; exit 2; }
PREFIX=$(readlink -f "$PREFIX_IN")
LOG_DIR="$REVIT_LOGS/$(basename "$PREFIX")"
mkdir -p "$LOG_DIR"

FAIL=0
step()    { printf '\n== %s\n' "$*"; }
ok()      { printf '  [ ok ]      %s\n' "$*"; }
note()    { printf '  [note]      %s\n' "$*"; }
warn()    { printf '  [warn]      %s\n' "$*"; }
missing() { printf '  [MISSING]   %s\n' "$*"; FAIL=1; }

# ------------------------------------------------------------ 0. sanity ------
[ -x "$WINE" ]           || missing "patched Wine build at $WINE (run tools/build_wine.sh)"
[ -f "$MEDIA/Setup.exe" ] || missing "media incomplete: $MEDIA/Setup.exe (needs Setup.exe + ODIS/)"
[ -d "$MEDIA/ODIS" ]      || missing "media incomplete: $MEDIA/ODIS"
[ "$FAIL" = 0 ] || exit 1

REVIT_EXE="$PREFIX/drive_c/Program Files/Autodesk/Revit 2027/Revit.exe"

# ------------------------------------------------------------ 1. prefix ------
step "1. create prefix (win64, Windows 10)"
if [ -s "$PREFIX/system.reg" ]; then
  note "prefix already exists at $PREFIX"
else
  mkdir -p "$PREFIX"
  WINEARCH=win64 WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" "$WINE" wineboot -u \
      > "$LOG_DIR/wineboot.log" 2>&1
  for _ in $(seq 1 150); do
    [ -s "$PREFIX/system.reg" ] && [ -s "$PREFIX/user.reg" ] && break
    sleep 2
  done
  WINEPREFIX="$PREFIX" "$WINE" wineserver -w 2>/dev/null || true
  [ -s "$PREFIX/system.reg" ] || { missing "wineboot produced no $PREFIX/system.reg"; exit 1; }
  ok "created prefix with wineboot -u (win64, Windows 10)"
fi
grep -q '#arch=win64' "$PREFIX/system.reg" || { missing "$PREFIX is not a win64 prefix"; exit 1; }
ok "$("$WINE" --version) prefix, arch=win64"

# ------------------------------------------------------------ 2. install -----
step "2. unattended Autodesk install (Setup.exe -q)"
if [ -f "$REVIT_EXE" ] && [ "$FORCE_INSTALL" = 0 ]; then
  note "Revit already installed ($REVIT_EXE)"
else
  ilog="$LOG_DIR/install.log"
  printf '  running: (cd %s && Setup.exe -q)  -> %s\n' "$MEDIA" "$ilog"
  # Post-install actions (see tools/neutralize_postinstall.py): three of the bundle's
  # `<CustomCommands>` actions are PowerShell-hosted launchers (RCPCOM's
  # Revit_DictionaryPermissions.exe and its powershell preUninstall, RCLRVTSMPL's
  # Revit2027_SamplesAttributes.exe).  With no working PowerShell in the prefix they exit non-zero,
  # and RCPCOM — the 1.5 GB program package — has no ignoreFailure, so its failure makes the install
  # manager roll the whole bundle back (12 uninstall passes, then HandleCrash).  The watcher removes
  # those actions from the package manifests as soon as the download phase writes them, which is
  # before the install phase reads them.
  WATCH_PID=0
  if [ "${REVIT_ADIX_FIX:-1}" = 1 ]; then
    setsid nohup "$ROOT/tools/neutralize_postinstall.py" "$PREFIX" --watch "${INSTALL_TIMEOUT:-7200}" \
        > "$LOG_DIR/neutralize_postinstall.log" 2>&1 < /dev/null &
    WATCH_PID=$!
    note "post-install action watcher started (pid $WATCH_PID; log $LOG_DIR/neutralize_postinstall.log)"
  fi
  # NOTE on WINEDLLOVERRIDES: only mshtml is disabled (no Gecko). mscoree stays at its
  # default load order — Revit's bundle has IL-only .NET executables (RegisterCOM.exe ...)
  # and disabling mscoree makes them fail with c0000135 ("IL-only binary cannot be loaded"),
  # which is what the AutoCAD recipe's 'mscoree,mshtml=' does.  See README "differences".
  ( cd "$MEDIA" && WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" \
      WINEDLLOVERRIDES="${REVIT_DLLOVERRIDES:-mshtml=}" \
      timeout "${INSTALL_TIMEOUT:-7200}" "$WINE" ./Setup.exe -q ) > "$ilog" 2>&1
  rc=$?
  if [ "$WATCH_PID" != 0 ]; then
    kill "$WATCH_PID" 2>/dev/null || true
    WINEPREFIX="$PREFIX" "$WINE" wineserver -w 2>/dev/null || true
    note "post-install action watcher: $(grep -c 'dropped' "$LOG_DIR/neutralize_postinstall.log" 2>/dev/null || echo 0) action(s) dropped"
  fi
  WINEPREFIX="$PREFIX" "$WINE" wineserver -w 2>/dev/null || true
  ok "Setup.exe exited rc=$rc after $(wc -l < "$ilog") log lines  ($ilog)"
  grep -qa 'install_mode uninstall' "$ilog" \
    && warn "the installer log contains an ODIS uninstall pass (see README: delegate update)"
fi

# --------------------------------------------------- 2c. skipped packages ----
# If the install manager aborts (CERWrapperImpl::HandleCrash) the packages still queued are never
# downloaded at all, and the program directory keeps missing files that no staging-tree repair can
# supply (RCPCOMEXT -> Qt6Core.dll/Qt6Gui.dll/... that DesktopMFC.dll imports).  See README
# "Packages ODIS never downloads".
if [ "${REVIT_FETCH_MISSING:-1}" = 1 ]; then
  step "2c. complete packages ODIS did not download"
  fpy=python3; [ -x "$ROOT/tools/venv/bin/python" ] && fpy="$ROOT/tools/venv/bin/python"
  "$fpy" "$ROOT/tools/fetch_missing_packages.py" "$PREFIX" ${FETCH_ARGS:-} \
      > "$LOG_DIR/fetch_missing.log" 2>&1 \
    && ok "fetched: $(tail -1 "$LOG_DIR/fetch_missing.log")" \
    || warn "fetch_missing_packages.py failed — see $LOG_DIR/fetch_missing.log"
fi
[ -f "$REVIT_EXE" ] && ok "Revit.exe present" || missing "Revit.exe ABSENT ($REVIT_EXE)"

# ------------------------------------------------------------ 3. fixups ------
if [ "$INSTALL_ONLY" = 0 ]; then
  step "3. environment fixups (Wine-vs-Windows only)"
  FONTS="$PREFIX/drive_c/windows/Fonts"; mkdir -p "$FONTS"
  if [ ! -s "$FONTS/arial.ttf" ] && [ -x "$ROOT/tools/venv/bin/python" ]; then
    "$ROOT/tools/venv/bin/python" "$ROOT/tools/make_wine_fonts.py" "$FONTS" >/dev/null 2>&1
  fi
  wrun() { WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" "$WINE" "$@"; }
  wrun reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v 'Arial (TrueType)' /t REG_SZ /d 'C:\windows\Fonts\arial.ttf' /f >/dev/null 2>&1
  wrun reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v 'Arial Bold (TrueType)' /t REG_SZ /d 'C:\windows\Fonts\arialbd.ttf' /f >/dev/null 2>&1
  wrun reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v 'Microsoft Sans Serif (TrueType)' /t REG_SZ /d 'micross.ttf' /f >/dev/null 2>&1
  HOSTS="$PREFIX/drive_c/windows/system32/drivers/etc/hosts"
  mkdir -p "$(dirname "$HOSTS")"
  grep -q 'installed-components.autodesk' "$HOSTS" 2>/dev/null \
    || echo '127.0.0.1 installed-components.autodesk' >> "$HOSTS"
  for svc in RpcSs SamSs; do
    wrun reg add "HKLM\\System\\CurrentControlSet\\Services\\$svc" /v Start /t REG_DWORD /d 2 /f >/dev/null 2>&1
  done
  wrun reg add 'HKCU\Environment' /v WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS /t REG_SZ /d '--disable-gpu' /f >/dev/null 2>&1
  ok "fonts + hosts + RpcSs/SamSs + WebView2 flags applied"
fi

# ------------------------------------------------------------ 4. report ------
step "4. end state"
if [ -d "$PREFIX/drive_c/Program Files/Autodesk/Revit 2027" ]; then
  ok "Revit 2027 = $(du -sh "$PREFIX/drive_c/Program Files/Autodesk/Revit 2027" 2>/dev/null | cut -f1), $(ls "$PREFIX/drive_c/Program Files/Autodesk/Revit 2027" | wc -l) entries"
else
  missing "no Program Files/Autodesk/Revit 2027"
fi
O="$PREFIX/drive_c/users/$(whoami)/AppData/Local/Autodesk/ODIS"
[ -f "$O/Summary.log" ] && printf '  packages INSTALLED: %s   (of %s states)\n' \
  "$(grep -ac 'Install State: INSTALLED' "$O/Summary.log")" "$(grep -ac 'Install State' "$O/Summary.log")"
for db in Install.db Package.db; do
  [ -f "$O/$db" ] && cp "$O/$db" "$LOG_DIR/" && note "copied $db to $LOG_DIR/"
done
printf '\nlogs: %s\n' "$LOG_DIR"
exit "$FAIL"
