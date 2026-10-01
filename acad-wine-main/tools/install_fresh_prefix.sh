#!/bin/bash
# =============================================================================
# tools/install_fresh_prefix.sh — take an EMPTY Wine prefix to a working AutoCAD 2027
# =============================================================================
#
# usage: tools/install_fresh_prefix.sh <prefix-path> [--install-only] [--repair] [--force-install]
#
#   (default)        create the prefix, run the unattended Autodesk install, then apply the
#                    environment fixups that a Wine prefix needs (see "3." below), and report.
#   --install-only   stop after the install + installer-output measurement: leave the prefix
#                    holding exactly what the installer produced. This is the acceptance path
#                    (see FINDINGS MILESTONE 25) — run tools/verify_fresh_prefix.sh on it after.
#   --repair         additionally apply the installer-defect workarounds (see "4." below).
#                    Only for a prefix whose install is genuinely incomplete; a normal install
#                    does not need any of them.
#   --force-install  run the installer even if acad.exe is already present.
#
# What the pipeline does:
#
#   0. sanity checks (patched Wine build, install media, reference data)
#   1. create the prefix                     wineboot -u, win64, Windows 10 (matches the
#                                            hand-polished reference prefix `$ROOT/prefix`)
#   2. unattended Autodesk install           ./Setup.exe -q from $ROOT/installer, the same
#                                            invocation the historical successful runs used
#   2b. installer-output measurement         ODIS DB counts vs the Windows guest's, both app
#                                            packages INSTALLED, installer logs, licensing
#                                            feature record, payload files, support tree ...
#   3. environment fixups                    Wine-vs-Windows differences only (fonts, hosts,
#                                            RpcSs/SamSs, WebView2 flag, plugin vectors)
#   4. repair mode (--repair only)           workarounds for an incomplete install
#   5. summary                               installer output vs fixups applied
#
# HISTORY / why so few fixups: earlier work (FINDINGS M19-M21, M24y, M24ah) concluded that ODIS
# never installs the acadprivate/acadps packages under Wine and that the licensing feature
# registration had to be applied by hand. That premise was REFUTED in M24am: a plain
# `Setup.exe -q` into a fresh prefix with the current build (patches 0001..0014) writes the
# same ODIS application/package map as Windows (Application=1, BundleAppPackages=35,
# Package=61, Package.db File=6473), installs "ACAD Private" and "AutoCAD 2027 - English", and
# registers prodKey 001S1/2027.0.0.F through the acadprivate MSI's own custom actions. The old
# Application=0 readings came from prefixes that had an ODIS *uninstall* pass run over them
# (prefix/, prefix.clean_failed/), which deletes the Application row. The workarounds are kept
# in "4." (--repair) for such prefixes, but the acceptance run does not use them.
#
# Everything here is required for the end state (acad launches, no licence-error dialog, the
# licensing UI reaches /ui/v2/lgs and paints, acad's UI renders with a drawing and zero
# assertion dialogs) — see FINDINGS.md "MILESTONE 25".
#
# The script never touches the shared reference prefix; pass it and it refuses.
# Logs: $ROOT/logs/freshinstall/<prefix-name>/
# =============================================================================
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Overridable so the scripts do not depend on where a particular checkout put things:
#   ACAD_WINE=<patched wine binary>   ACAD_MEDIA=<dir with Setup.exe + ODIS/>
WINE=${ACAD_WINE:-$ROOT/wine-install/bin/wine}
MEDIA=${ACAD_MEDIA:-$ROOT/installer}
REFERENCE_PREFIX=$ROOT/prefix          # the hand-polished prefix; never modified here
ACAD_SUBPATH='drive_c/Program Files/Autodesk/AutoCAD 2027'
ADSK_SUBPATH='drive_c/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing'
PROD_KEY=001S1
PROD_VER=2027.0.0.F

# the Windows guest's reference numbers for the ODIS map (vmshare/ODIS_Install.db), M24am
GUEST_PACKAGE=61; GUEST_APPLICATION=1; GUEST_BUNDLEAPPPACKAGES=35; GUEST_PACKAGEFILE=6473

DO_INSTALL=1
FORCE_INSTALL=0
INSTALL_ONLY=0
REPAIR=0
for arg in "$@"; do
  case "$arg" in
    --install-only)  INSTALL_ONLY=1 ;;
    --repair)        REPAIR=1 ;;
    --force-install) FORCE_INSTALL=1 ;;
    -h|--help)       sed -n '2,40p' "$0"; exit 0 ;;
    -*)              echo "unknown option: $arg" >&2; exit 2 ;;
    *)               PREFIX_IN="$arg" ;;
  esac
done

[ -n "${PREFIX_IN:-}" ] || { echo "usage: $0 <prefix-path> [--install-only] [--repair] [--force-install]" >&2; exit 2; }
PREFIX=$(readlink -f "$PREFIX_IN" 2>/dev/null || echo "$PREFIX_IN")
case "$PREFIX" in
  "$REFERENCE_PREFIX"|"$REFERENCE_PREFIX"/*)
      echo "refusing to run against the shared reference prefix $REFERENCE_PREFIX" >&2; exit 2 ;;
esac

DISPLAY_X=${DISP:-:2}                  # the VNC display the project's UI runs use
LOG_DIR=$ROOT/logs/freshinstall/$(basename "$PREFIX")
mkdir -p "$LOG_DIR"
MAIN_LOG=$LOG_DIR/pipeline.log
: > "$MAIN_LOG"

# ---------------------------------------------------------------- reporting ---
# Three verdicts, so a run produces the "installer produced / we had to add" table directly.
PRESENT=(); FIXED=(); MISSING=()
ts()   { date +%H:%M:%S; }
log()  { printf '%s %s\n' "$(ts)" "$*" | tee -a "$MAIN_LOG"; }
step() { printf '\n%s === %s\n' "$(ts)" "$*" | tee -a "$MAIN_LOG"; }
present() { log "  [present]   $*"; PRESENT+=("$*"); }
fix()     { log "  [fixup]     $*"; FIXED+=("$*"); }
missing() { log "  [MISSING]   $*"; MISSING+=("$*"); }
skip()    { log "  [skip]      $*"; }
die()     { log "FATAL: $*"; exit 1; }

# wine invocation for this prefix (never inherits the caller's WINEPREFIX)
wrun() { WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" "$WINE" "$@"; }
reg_query() { wrun reg query "$1" /v "$2" >/dev/null 2>&1; }
reg_add()   { wrun reg add "$1" /v "$2" /t "${4:-REG_SZ}" /d "$3" /f >/dev/null 2>&1; }
acad_dir()  { echo "$PREFIX/$ACAD_SUBPATH"; }
# `wine path -w` for a host path
win_path() { WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" "$WINE" winepath -w "$1" 2>/dev/null || echo "$1"; }

log "prefix     : $PREFIX"
log "wine       : $WINE ($("$WINE" --version 2>/dev/null))"
log "display    : $DISPLAY_X"
log "log dir    : $LOG_DIR"
log "mode       :$([ "$INSTALL_ONLY" = 1 ] && echo ' install-only')$([ "$REPAIR" = 1 ] && echo ' repair')"

# --------------------------------------------------------------- 0. sanity ----
step "0. sanity checks"
[ -x "$WINE" ]                    || die "patched Wine build missing: $WINE (build it with tools/build_wine.sh, or set ACAD_WINE)"
[ -d "$MEDIA" ]                   || die "install media missing: $MEDIA (put your Autodesk ODIS media there, or set ACAD_MEDIA - see SETUP.md)"
[ -f "$MEDIA/Setup.exe" ]         || die "install media incomplete: $MEDIA/Setup.exe (needs Setup.exe and ODIS/)"
[ -d "$MEDIA/ODIS" ]              || die "install media incomplete: $MEDIA/ODIS missing"
log "  ok: wine, media"

# ------------------------------------------------------------ 1. the prefix ---
step "1. create prefix (win64, Windows 10 — same as the reference prefix)"
if [ -s "$PREFIX/system.reg" ]; then
  present "prefix already exists at $PREFIX"
else
  mkdir -p "$PREFIX"
  WINEARCH=win64 WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" "$WINE" wineboot -u \
      > "$LOG_DIR/wineboot.log" 2>&1
  # wineboot returns before its second phase (wine.inf/msi processing) has written the registry,
  # so wait for the hive files and for every helper it started to exit.
  for _ in $(seq 1 150); do
    [ -s "$PREFIX/system.reg" ] && [ -s "$PREFIX/user.reg" ] && break
    sleep 2
  done
  WINEPREFIX="$PREFIX" "$WINE" wineserver -w 2>/dev/null || true
  [ -s "$PREFIX/system.reg" ] || die "wineboot did not produce $PREFIX/system.reg (see $LOG_DIR/wineboot.log)"
  fix "created prefix with wineboot -u (win64, Windows 10)"
fi
grep -q '#arch=win64' "$PREFIX/system.reg" || die "$PREFIX is not a win64 prefix"
log "  ok: $("$WINE" --version) prefix, arch=win64"

# ------------------------------------------------------------- 2. install ----
ACAD=$(acad_dir)
step "2. unattended Autodesk install (Setup.exe -q)"
if [ -f "$ACAD/acad.exe" ] && [ "$FORCE_INSTALL" = 0 ]; then
  present "AutoCAD already installed ($ACAD/acad.exe)"
elif [ "$DO_INSTALL" = 0 ]; then
  skip "install disabled"
else
  # The install takes tens of minutes (it downloads the ODIS packages). `Setup.exe -q` is the
  # invocation the historical successful runs used (run_installer.sh): ODIS + ASC run in silent
  # mode, and mscoree/mshtml are disabled for the installer's own .NET/Gecko parts.
  #
  # Known Wine-side failure mode: a later ODIS pass can run
  #   Installer.exe --manifest <ASC bundle> --install_mode uninstall --delegate_type
  #                   DELEGATE_UPDATE_PACKAGE --silent
  # and cascade-uninstall what was just installed (FINDINGS M20, seen in prefix.clean_failed).
  # Such a pass also *deletes the ODIS Application row* (M24am), so a prefix that has seen one
  # needs the --repair path. We therefore check the product after the run and retry once with a
  # fresh prefix.
  attempt=0
  while :; do
    attempt=$((attempt + 1))
    ilog=$LOG_DIR/install_attempt${attempt}.log
    log "  running: (cd $MEDIA && Setup.exe -q)  -> $ilog"
    ( cd "$MEDIA" && WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" \
        WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG="${INSTALL_WINEDEBUG:-+msi}" \
        timeout "${INSTALL_TIMEOUT:-7200}" "$WINE" ./Setup.exe -q ) > "$ilog" 2>&1
    rc=$?
    # let every helper ODIS started (install_manager, msiexec, ...) finish before we look
    WINEPREFIX="$PREFIX" "$WINE" wineserver -w 2>/dev/null || true
    log "  Setup.exe exited rc=$rc after $(wc -l < "$ilog") log lines"
    if [ -f "$ACAD/acad.exe" ]; then
      if grep -qa 'install_mode uninstall' "$ilog"; then
        log "  WARNING: the log contains an ODIS uninstall pass (it deletes the Application row)"
      fi
      fix "ran the unattended install (attempt $attempt): $ilog"
      break
    fi
    [ "$attempt" -lt 3 ] || die "install produced no acad.exe after $attempt attempts (see $ilog)"
    log "  no acad.exe yet; retrying with a fresh prefix"
    rm -rf "$PREFIX"
    WINEARCH=win64 WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" "$WINE" wineboot -u \
        > "$LOG_DIR/wineboot_r$attempt.log" 2>&1
    WINEPREFIX="$PREFIX" "$WINE" wineserver -w 2>/dev/null || true
  done
fi
DISPLAY_X="$DISPLAY_X" log "  acad.exe: $([ -f "$ACAD/acad.exe" ] && echo present || echo ABSENT)"

# ------------------------------------- 2b. what the installer actually made ---
step "2b. installer-output measurement (vs the Windows guest's numbers)"
GUEST_PACKAGE=61 GUEST_APPLICATION=1 GUEST_BUNDLEAPPPACKAGES=35 GUEST_PACKAGEFILE=6473 \
"$ROOT/tools/venv/bin/python" - "$PREFIX" <<'PY' 2>&1 | tee -a "$MAIN_LOG"
import os, shutil, sqlite3, sys, tempfile
prefix = sys.argv[1]
expected = {
    "Install.db": {"Package": 61, "Application": 1, "BundleAppPackages": 35},
    "Package.db": {"File": 6473},
}
for name, want in expected.items():
    src = os.path.join(prefix, "drive_c/ProgramData/Autodesk/ODIS", name)
    if not os.path.exists(src):
        print(f"  {name:12s} ABSENT (the installer never wrote it)")
        continue
    tmp = tempfile.mktemp(suffix=".db"); shutil.copy(src, tmp)   # the live DB is locked
    try:
        con = sqlite3.connect(tmp)
        for table, guest in want.items():
            try:
                got = con.execute(f"select count(*) from {table}").fetchone()[0]
                flag = "ok  " if got == guest else "DIFF"
                print(f"  {name:12s} {table:18s} = {got:5d}   guest={guest:5d}  {flag}")
            except Exception as e:
                print(f"  {name:12s} {table:18s} : {e}")
        con.close()
    finally:
        os.unlink(tmp)
PY

# both application packages must be INSTALLED, and their own installer logs must exist
tmp_acad="$PREFIX/drive_c/users/$(whoami)/AppData/Local/Temp"
summary=$(ls "$tmp_acad"/*/Summary.log "$tmp_acad"/../Autodesk/ODIS/Summary.log \
              "$PREFIX/drive_c/users/$(whoami)/AppData/Local/Autodesk/ODIS/Summary.log" 2>/dev/null | head -1)
if [ -n "$summary" ]; then
  for pkg in 'ACAD Private' 'AutoCAD 2027 - English'; do
    if awk -v p="$pkg" '$0 ~ p {found=1} found && /Install State: INSTALLED/ {ok=1; exit} END {exit !ok}' "$summary"; then
      present "package installed: $pkg"
    else
      missing "package NOT installed: $pkg (see $summary)"
    fi
  done
else
  missing "no ODIS Summary.log found under $tmp_acad"
fi
for pat in 'Autodesk_AutoCAD_Private*' 'Autodesk_AutoCAD_PSPack*' 'AdskLicensing-install.log'; do
  f=$(ls "$tmp_acad"/$pat 2>/dev/null | head -1)
  [ -n "$f" ] && present "installer log: $(basename "$f")" || missing "installer log absent: $pat"
done

# acadprivate payload (acad loads AcJab.dll; its absence is licensing code 20001)
priv_missing=0
for f in AcJab.dll AdMigrator.xml Support/AcCommandWeight.xml MsiKeyFile/MsiKeyFile_LEGACYCODESEARCH.dll; do
  [ -f "$ACAD/$f" ] || priv_missing=$((priv_missing+1))
done
[ "$priv_missing" = 0 ] && present "acadprivate payload (AcJab.dll, AdMigrator.xml, MsiKeyFile, Support)" \
                        || missing "$priv_missing acadprivate payload file(s) absent"

# per-user support tree (the SystemVariable/profile dirs acad reads its CUIX from)
ROAM="$PREFIX/drive_c/users/$(whoami)/AppData/Roaming/Autodesk/AutoCAD 2027/R26.0/enu/Support"
[ -f "$ROAM/acad.CUIX" ] && present "per-user support tree ($ROAM/*.cuix)" \
                        || missing "per-user support tree absent ($ROAM/acad.CUIX)"
reg_query 'HKLM\Software\Autodesk\AutoCAD\R26.0\ACAD-A101\SupportFiles' DefaultSearchPaths \
  && present "SupportFiles\\DefaultSearchPaths (PSPack)" \
  || missing "SupportFiles\\DefaultSearchPaths absent (PSPack did not run)"

# licensing: component version, registry keys, and the prodKey feature record
LICDIR="$PREFIX/$ADSK_SUBPATH"
[ -f "$LICDIR/version.ini" ] && present "AdskLicensing\\version.ini ($(grep -a version "$LICDIR/version.ini" | head -1))" \
                            || missing "AdskLicensing\\version.ini absent"
reg_query 'HKLM\Software\Autodesk\AdskLicensing' Version \
  && present "HKLM\\Software\\Autodesk\\AdskLicensing = $(wrun reg query 'HKLM\Software\Autodesk\AdskLicensing' /v Version 2>/dev/null | grep -a Version | awk '{print $NF}')" \
  || missing "HKLM\\Software\\Autodesk\\AdskLicensing absent"
reg_query 'HKLM\Software\Autodesk\AdskIdentityManager\1.19.2.0' Location \
  && present "HKLM\\Software\\Autodesk\\AdskIdentityManager\\1.19.2.0" \
  || missing "HKLM\\Software\\Autodesk\\AdskIdentityManager\\1.19.2.0 absent"
SDS="$PREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService/AdskLicensingService.sds"
if [ -f "$SDS" ] && strings -n 8 "$SDS" | grep -q "$PROD_KEY"; then
  present "licensing feature record $PROD_KEY/$PROD_VER in AdskLicensingService.sds"
else
  missing "no licensing feature record for $PROD_KEY in AdskLicensingService.sds"
fi
# the helper's own view of the registration (feature_id ACD). Look the helper up by versioned
# directory (Wine represents the `Current` junction on the Unix side as `Current?`, which the
# Unix-side path below cannot traverse - inside Wine, Current resolves fine).
licver=$(ls -d "$LICDIR"/*/ 2>/dev/null | sed 's|/$||' | grep -E '/[0-9]+(\.[0-9]+)+$' | sort -V | tail -1); licver=${licver##*/}
helper_win="C:\\Program Files (x86)\\Common Files\\Autodesk Shared\\AdskLicensing\\${licver:-16.6.0.16341}\\helper\\AdskLicensingInstHelper.exe"
if [ -n "$licver" ]; then
  list=$(WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" WINEDLLOVERRIDES="mshtml=" timeout 180 \
           "$WINE" "$helper_win" list 2>&1 | grep -av 'fixme' | head -8)
  feats=$(printf '%s' "$list" | grep -ao '"feature_id": *"[^"]*"\|"sel_prod_key": *"[^"]*"\|"sel_prod_ver": *"[^"]*"' | tr '\n' ' ')
  if printf '%s' "$feats" | grep -q "$PROD_KEY"; then
    present "AdskLicensingInstHelper list: $feats"
  else
    missing "AdskLicensingInstHelper list has no $PROD_KEY feature (got: ${feats:-nothing})"
  fi
fi

# .NET desktop runtime (acad's mixed-mode assemblies need CoreCLR 10)
if [ -f "$PREFIX/drive_c/Program Files/dotnet/dotnet.exe" ]; then
  present ".NET Desktop Runtime $({ ls "$PREFIX/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App" 2>/dev/null; } | head -1)"
else
  missing ".NET Desktop Runtime (C:\\Program Files\\dotnet\\dotnet.exe)"
fi
# product identity file (acad reads its registry root from here)
[ -f "$ACAD/en-US/identity.ini" ] && present "en-US/identity.ini" || missing "en-US/identity.ini"

if [ "$INSTALL_ONLY" = 1 ]; then
  step "stop after the install (--install-only): the prefix holds exactly what the installer produced"
  printf '  installer output verified: %d present, %d missing\n' "${#PRESENT[@]}" "${#MISSING[@]}" | tee -a "$MAIN_LOG"
  [ "${#MISSING[@]}" = 0 ] || { printf '  missing: %s\n' "${MISSING[@]}" | tee -a "$MAIN_LOG"; }
  exit 0
fi

# ------------------------------------------- 3. environment fixups (Wine) -----
step "3. environment fixups (differences between Wine's prefix and Windows, not installer defects)"

# 3a. Fonts.  acad's WPF UI asks for the families "Arial" and "Microsoft Sans Serif"; a Wine
#     prefix ships neither, and WPF/DirectWrite does not consult Wine's GDI FontSubstitutes, so
#     the UI never lays out (blank window, FINDINGS M18/M25). The files are built from fonts that
#     are already on the machine (see tools/make_wine_fonts.py) and registered under the same key
#     Windows uses.
FONTS="$PREFIX/drive_c/windows/Fonts"
need_fonts=0
for f in arial.ttf arialbd.ttf micross.ttf; do
  [ -f "$FONTS/$f" ] || need_fonts=1
done
if [ "$need_fonts" = 0 ]; then
  present "Arial/Arial Bold/Microsoft Sans Serif font files"
else
  mkdir -p "$FONTS"
  "$ROOT/tools/venv/bin/python" "$ROOT/tools/make_wine_fonts.py" "$FONTS" >> "$MAIN_LOG" 2>&1 \
    || die "font build failed (see $MAIN_LOG)"
  fix "built + installed arial.ttf, arialbd.ttf, micross.ttf (Wine ships no Arial; tools/make_wine_fonts.py)"
fi
FONTKEY='HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
register_font() {   # name, value
  if reg_query "$FONTKEY" "$1"; then present "font registry entry: $1"; else
    reg_add "$FONTKEY" "$1" "$2"; fix "font registry entry: $1 = $2"; fi
}
register_font 'Arial (TrueType)'                'C:\windows\Fonts\arial.ttf'
register_font 'Arial Bold (TrueType)'           'C:\windows\Fonts\arialbd.ttf'
register_font 'Microsoft Sans Serif (TrueType)' 'micross.ttf'

# 3b. hosts entry.  The licensing SDK resolves the AppHome host
#     `installed-components.autodesk`; Wine only honours the Windows hosts file thanks to
#     patches/0006-ws2_32-windows-hosts-file.patch, so the name must be in it (FINDINGS M24u).
HOSTS="$PREFIX/drive_c/windows/system32/drivers/etc/hosts"
mkdir -p "$(dirname "$HOSTS")"
if grep -q 'installed-components.autodesk' "$HOSTS" 2>/dev/null; then
  present "hosts entry for installed-components.autodesk"
else
  echo '127.0.0.1 installed-components.autodesk' >> "$HOSTS"
  fix "hosts entry installed-components.autodesk -> 127.0.0.1 (Wine hosts file, patch 0006)"
fi

# 3c. RpcSs/SamSs must start automatically: the licensing SDK enumerates the machine security
#     services and Wine's default for both is demand-start (Start=3) (FINDINGS M24t).
for svc in RpcSs SamSs; do
  key="HKLM\\System\\CurrentControlSet\\Services\\$svc"
  cur=$(wrun reg query "$key" /v Start 2>/dev/null | grep -ao '0x[0-9a-f]*' | tail -1)
  if [ "$cur" = "0x2" ]; then present "$svc\\Start=2"
  else reg_add "$key" Start 2 REG_DWORD; fix "$svc\\Start=2 (Wine default is demand-start)"; fi
done

# 3d. WebView2 paint flag.  Both acad's webview and the licensing agent's own webview (launched
#     by the service, so it does not inherit acad's environment) need --disable-gpu or their
#     Chromium surface never paints under Wine (FINDINGS M24af). This is a runtime setting, not
#     an install fixup - the registry value is what acad and the agent read.
if reg_query 'HKCU\Environment' WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS; then
  present 'HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS'
else
  reg_add 'HKCU\Environment' WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS '--disable-gpu'
  fix 'HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu'
fi

# 3e. plugin autoload vectors: a stock prefix has none, but plug_wire.sh can leave them behind and
#     they change acad's startup.  Remove them so the prefix matches a stock install.
unwired=0
for K in 'ACAD-A101' 'ACAD-A101:409'; do
  if wrun reg query "HKCU\\Software\\Autodesk\\AutoCAD\\R26.0\\$K\\Applications\\WineProbe" >/dev/null 2>&1; then
    wrun reg delete "HKCU\\Software\\Autodesk\\AutoCAD\\R26.0\\$K\\Applications\\WineProbe" /f >/dev/null 2>&1
    unwired=1
  fi
done
for v in 'HKLM\Software\Autodesk\AutoCAD\R26.0\ACAD-A101\Variables' \
         'HKCU\Software\Autodesk\AutoCAD\R26.0\ACAD-A101\Variables'; do
  if reg_query "$v" TRUSTEDPATHS; then wrun reg delete "$v" /v TRUSTEDPATHS /f >/dev/null 2>&1; unwired=1; fi
done
[ -f "$ROAM/acad.lsp" ] && { rm -f "$ROAM/acad.lsp"; unwired=1; }
PLUGDIR="$PREFIX/drive_c/users/$(whoami)/AppData/Roaming/Autodesk/ApplicationPlugins/WineFix.bundle"
[ -d "$PLUGDIR" ] && { rm -rf "$PLUGDIR"; unwired=1; }
[ "$unwired" = 0 ] && present "no plugin autoload vectors (stock install)" \
                   || fix "removed leftover plugin autoload vectors (WineProbe/acad.lsp/bundle/TRUSTEDPATHS)"

# ------------------------------------- 4. repair mode (installer defects) -----
# Only for a prefix whose installer output is incomplete (see the header): the historical
# workarounds for the "ODIS drops acadprivate/acadps" diagnosis, plus the licensing registration.
if [ "$REPAIR" = 1 ]; then
  step "4. repair mode (--repair): installer-defect workarounds"

  # 4a. product identity file, if the installer did not write it
  IDENTITY="$ACAD/en-US/identity.ini"
  if [ -f "$IDENTITY" ]; then present "en-US/identity.ini"
  else
    mkdir -p "$ACAD/en-US"
    cat > "$IDENTITY" <<'EOF'
[ProductIdentity]
ProductRegistryRootKey=Software\Autodesk\AutoCAD\R26.0\ACAD-A101:409
GlobalRegistryRootKey=Software\Autodesk\AutoCAD\R26.0\ACAD-A101
EOF
    fix "en-US/identity.ini (product identity; FINDINGS M17)"
  fi

  # 4b. acadprivate MSI: installs the payload AcJab.dll and runs the licensing custom actions
  #     (licMarkInstall / licRegister).  Do NOT pass INSTALLDIR with a trailing backslash: Wine's
  #     msiexec quotes values containing spaces and msi_parse_command_line then fails (exit 103,
  #     header-only log); the MSI's own Directory table resolves the product dir.  See the gap
  #     table in FINDINGS M25 for whether this invocation hit the msiexec bug.
  PRIV_MSI="$ROOT/pkgs/x/x64/acadprivate/acadprivate.msi"
  SDS="$PREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService/AdskLicensingService.sds"
  feature_registered() { [ -f "$SDS" ] && strings -n 8 "$SDS" | grep -q "$PROD_KEY"; }
  if [ -f "$PRIV_MSI" ] && { [ ! -f "$ACAD/AcJab.dll" ] || ! feature_registered; }; then
    log "  msiexec /i acadprivate.msi /qn MSIFASTINSTALL=7 ARPSYSTEMCOMPONENT=1 REBOOT=ReallySuppress ADSK_ODIS_SETUP=1"
    WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" WINEDLLOVERRIDES="mshtml=" timeout 900 \
      "$WINE" msiexec /i "$(win_path "$PRIV_MSI")" /qn \
      MSIFASTINSTALL=7 ARPSYSTEMCOMPONENT=1 REBOOT=ReallySuppress ADSK_ODIS_SETUP=1 \
      > "$LOG_DIR/acadprivate_msi.log" 2>&1
    log "  msiexec rc=$? (log: $LOG_DIR/acadprivate_msi.log)"
    sleep 5
  fi

  # 4c. acadprivate payload: copy whatever the MSI above did not install
  PRIV_SRC="$ROOT/pkgs/x/x64/acadprivate/PF/Root"
  priv_missing=0
  for f in AcJab.dll AdMigrator.xml Support/AcCommandWeight.xml MsiKeyFile/MsiKeyFile_LEGACYCODESEARCH.dll; do
    [ -f "$ACAD/$f" ] || priv_missing=$((priv_missing+1))
  done
  if [ "$priv_missing" = 0 ]; then present "acadprivate payload"
  else
    mkdir -p "$ACAD/MsiKeyFile" "$ACAD/Support"
    ( cd "$PRIV_SRC" && tar cf - AcJab.dll AdMigrator.xml Support MsiKeyFile ) | ( cd "$ACAD" && tar xf - )
    fix "copied $priv_missing missing acadprivate payload file(s) from the media payload tree"
  fi

  # 4d. licensing feature registration: the helper sequence the Windows MSI custom actions run
  if feature_registered; then
    present "licensing feature record for $PROD_KEY (already registered)"
  else
    log "  running tools/fix_licensing_registration.sh (acadprivate custom-action fallback)"
    DISP="$DISPLAY_X" bash "$ROOT/tools/fix_licensing_registration.sh" "$PREFIX" \
      >> "$LOG_DIR/licensing_registration.log" 2>&1
    feature_registered && fix "licensing feature record registered by tools/fix_licensing_registration.sh" \
                       || missing "could not register the licensing feature record (see $LOG_DIR/licensing_registration.log)"
  fi

  # 4e. AdskIdentityManager registry key (present on Windows; no installer log even there)
  IMKEY='HKLM\Software\Autodesk\AdskIdentityManager\1.19.2.0'
  if reg_query "$IMKEY" Location; then present "AdskIdentityManager registry key"
  else
    reg_add "$IMKEY" Location 'C:\Program Files\Autodesk\AdskIdentityManager\1.19.2.0'
    reg_add "$IMKEY" UPI2 '{DA0DAFFC-6DE7-399A-9FC9-0D1456C9D809}'
    fix "AdskIdentityManager\\1.19.2.0 registry key"
  fi

  # 4f. en-US Product Support Pack MSI (acadps): the per-user support tree / CUIX
  PS_MSI="$ROOT/pkgs/x/x64/en-US/acadps/acadps.msi"; PS_MST="$ROOT/pkgs/x/x64/en-US/acadps/acadps.mst"
  if [ -f "$ROAM/acad.CUIX" ] && reg_query 'HKLM\Software\Autodesk\AutoCAD\R26.0\ACAD-A101\SupportFiles' DefaultSearchPaths; then
    present "per-user support tree + SupportFiles registry values"
  elif [ -f "$PS_MSI" ]; then
    PS_ARGS=(/i "$(win_path "$PS_MSI")" /qn MSIFASTINSTALL=7 ARPSYSTEMCOMPONENT=1 REBOOT=ReallySuppress \
             ADSK_ODIS_SETUP=1 ADSK_EULA_STATUS='#1')
    [ -f "$PS_MST" ] && PS_ARGS+=("TRANSFORMS=$(win_path "$PS_MST")")
    log "  msiexec ${PS_ARGS[*]}"
    WINEPREFIX="$PREFIX" DISPLAY="$DISPLAY_X" WINEDLLOVERRIDES="mshtml=" timeout 1800 \
      "$WINE" msiexec "${PS_ARGS[@]}" > "$LOG_DIR/acadps_msi.log" 2>&1
    log "  msiexec rc=$? (log: $LOG_DIR/acadps_msi.log)"
  else
    log "  WARNING: $PS_MSI missing; the CUIX copies below stand in for the package"
  fi

  # 4g. CUIX gap fill.  The copies come from the acadps payload archive's own UserDataCache
  #     tree; the Autodesk media is not kept in the tree, so point ACADPS_PAYLOAD at the
  #     archive (or ACADPS_CUIX_DIR at a harvested CUIX directory) if they live elsewhere.
  #     The archive ships 6 of the 9 files (acad.bak.cuix, AppManager.cuix and FeaturedApps.cuix
  #     come from acad and the ApplicationPlugins bundles); a missing source is left alone.
  PS_PAYLOAD="${ACADPS_PAYLOAD:-$ROOT/pkgs/pkg.acadps1.tar.xz}"
  CUISRC="${ACADPS_CUIX_DIR:-}"
  if [ -z "$CUISRC" ] && [ -f "$PS_PAYLOAD" ]; then
    CUISRC="$LOG_DIR/payload-cuix"; rm -rf "$CUISRC"; mkdir -p "$CUISRC"
    tar -xf "$PS_PAYLOAD" -C "$CUISRC" --wildcards '*/PF/Root/UserDataCache/*' 2>/dev/null
    UDC=$(find "$CUISRC" -type d -name UserDataCache -print -quit)
    if [ -n "$UDC" ]; then
      mkdir -p "$CUISRC/flat"
      find "$UDC" -maxdepth 2 -type f -iname '*.cuix' -exec cp -f {} "$CUISRC/flat/" \;
      CUISRC="$CUISRC/flat"
    else
      CUISRC=""
    fi
  fi
  if [ -n "$CUISRC" ]; then
    cuix_copied=0; cuix_present=0
    copy_cuix() { if [ -f "$2" ]; then cuix_present=$((cuix_present+1)); else
                    install -m 644 "$CUISRC/$1" "$2"; cuix_copied=$((cuix_copied+1)); fi; }
    mkdir -p "$ROAM" "$ACAD/UserDataCache/Support" "$ACAD/Support/en-US"
    for f in acad.CUIX acetmain.cuix ModelDoc.cuix custom.cuix dbcon.cuix; do
      copy_cuix "$f" "$ACAD/UserDataCache/Support/$f"; copy_cuix "$f" "$ACAD/Support/en-US/$f"; done
    copy_cuix AecArchxOE.cuix "$ACAD/UserDataCache/AecArchxOE.cuix"
    for f in acad.CUIX acad.bak.cuix acetmain.cuix ModelDoc.cuix custom.cuix dbcon.cuix; do
      copy_cuix "$f" "$ACAD/Support/$f"; done
    for f in acad.CUIX acad.bak.cuix acetmain.cuix ModelDoc.cuix custom.cuix dbcon.cuix \
             AecArchxOE.cuix AppManager.cuix FeaturedApps.cuix; do
      copy_cuix "$f" "$ROAM/$f"; done
    [ "$cuix_copied" = 0 ] && present "$cuix_present CUIX files (roaming tree + product Support)" \
                           || fix "copied $cuix_copied CUIX file(s) ($cuix_present already present)"
  else
    skip "CUIX gap fill: acadps payload archive not found ($PS_PAYLOAD)"
  fi

  # 4h. .NET Desktop Runtime, if the installer did not bring one (the Runtime zip carries
  #     dotnet.exe + host/fxr + Microsoft.NETCore.App, the WindowsDesktop zip the WPF frameworks)
  DOTNET="$PREFIX/drive_c/Program Files/dotnet/dotnet.exe"
  DOTNET_VER=10.0.9
  fetch_dotnet() {
    local base=https://builds.dotnet.microsoft.com/dotnet dst="$PREFIX/drive_c/Program Files/dotnet"
    mkdir -p "$dst"
    for z in "Runtime/${DOTNET_VER}/dotnet-runtime-${DOTNET_VER}-win-x64.zip" \
             "WindowsDesktop/${DOTNET_VER}/windowsdesktop-runtime-${DOTNET_VER}-win-x64.zip"; do
      local out=$LOG_DIR/$(basename "$z")
      log "  fetching $base/$z"
      curl -fsSL -o "$out" "$base/$z" || return 1
      unzip -q -o "$out" -d "$dst" || return 1
    done
    [ -f "$DOTNET" ]
  }
  if [ -f "$DOTNET" ]; then present ".NET Desktop Runtime"
  elif [ -d "$ROOT/pkgs/dotnet" ]; then
    mkdir -p "$PREFIX/drive_c/Program Files/dotnet"
    cp -a "$ROOT/pkgs/dotnet/." "$PREFIX/drive_c/Program Files/dotnet/"
    fix ".NET Desktop Runtime copied from pkgs/dotnet"
  elif fetch_dotnet; then fix ".NET Desktop Runtime $DOTNET_VER installed from builds.dotnet.microsoft.com"
  else missing ".NET Desktop Runtime could not be obtained (no download, no pkgs/dotnet)"; fi
else
  step "4. repair mode not requested (a normal install needs none of these workarounds)"
  log "  run with --repair if the installer output above is incomplete"
fi

# ------------------------------------------------------- 5. summary -----------
step "5. summary"
printf '\n%-72s\n' "PRODUCED BY THE INSTALLER (or an earlier run)" | tee -a "$MAIN_LOG"
for x in "${PRESENT[@]:-}"; do [ -n "$x" ] && printf '  + %s\n' "$x" | tee -a "$MAIN_LOG"; done
printf '\n%-72s\n' "ENVIRONMENT FIXUPS APPLIED BY THIS SCRIPT" | tee -a "$MAIN_LOG"
for x in "${FIXED[@]:-}";   do [ -n "$x" ] && printf '  * %s\n' "$x" | tee -a "$MAIN_LOG"; done
if [ "${#MISSING[@]}" -gt 0 ]; then
  printf '\n%-72s\n' "MISSING" | tee -a "$MAIN_LOG"
  for x in "${MISSING[@]}"; do printf '  ! %s\n' "$x" | tee -a "$MAIN_LOG"; done
fi

step "done"
log "prefix is ready: $PREFIX"
log "next: tools/verify_fresh_prefix.sh $PREFIX [seconds] [--apphome]   (launches acad and checks the end state)"
