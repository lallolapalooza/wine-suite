#!/bin/bash
# tools/install_pbi.sh — empty prefix → installed Power BI Desktop, unattended (acceptance A1/A5).
#
#   tools/install_pbi.sh <prefix-name> [options]
#     --skip-netfx          assume .NET Framework 4.8 is already in the prefix
#     --fonts DIR           font directory to install (default: fonts/)
#     --webview2 DIR        WebView2 runtime tree to deploy (a directory containing msedgewebview2.exe)
#     --webview2-version X  version to register for it (default: inferred from the tree's <version>.manifest)
#     --bootstrapper        install via PBIDesktopSetup_x64.exe instead of the MSI directly
#     --msi PATH            MSI to install (default: recon/msi/PBIDesktop_x64.msi)
#
# Stages, and why each exists (full evidence in FINDINGS.md M1–M5):
#   1 prefix            : wineboot -u with the project's wine (staging, or our fork once built)
#   2 .NET Framework    : the app is WPF/.NET 4.7.2+; wine-mono cannot run WPF, and the MSI's own managed
#                         custom actions crashed mono ("domain required for stack walk") — so a real
#                         .NET Framework 4.8 is a hard requirement.
#   3 fonts             : WPF asks for Segoe UI / Segoe MDL2 Assets; Wine ships neither.
#   4 WebView2 runtime  : the report canvas + start page are HTML/JS in WebView2. The Evergreen installer
#                         CANNOT run under Wine (fails 0x80040c01, picks the Windows 7/8 channel), so we
#                         deploy a runtime tree and point WebView2Loader at it.
#   5 install           : MSI directly, or the WiX Burn bootstrapper. Either way the MSI needs
#                         ACCEPT_EULA=1 (else LaunchCondition 1603 → Burn 0x80070643), and the WebView2
#                         custom action must be disabled (PBI_enableWebView2Install=false) or it pops the
#                         broken Evergreen UI at the user.
#   6 fixups            : WebView2/Chromium arguments via HKCU\Environment (registry wins over process env).
set -o pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PFX=${1:?usage: install_pbi.sh <prefix-name> [--skip-netfx] [--fonts DIR] [--webview2 DIR] [--bootstrapper]}
shift
SKIP_NETFX=0
FONTS_DIR=$ROOT/fonts
WEBVIEW2_DIR=""
WEBVIEW2_VERSION=""
USE_BOOTSTRAPPER=0
MSI=$ROOT/recon/msi/PBIDesktop_x64.msi
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-netfx) SKIP_NETFX=1; shift ;;
        --fonts) FONTS_DIR=$2; shift 2 ;;
        --webview2) WEBVIEW2_DIR=$2; shift 2 ;;
        --webview2-version) WEBVIEW2_VERSION=$2; shift 2 ;;
        --bootstrapper) USE_BOOTSTRAPPER=1; shift ;;
        --msi) MSI=$2; shift 2 ;;
        *) echo "unknown option: $1"; exit 2 ;;
    esac
done

source "$ROOT/tools/pbi_env.sh" "$PFX"
export WINEDLLOVERRIDES=${WINEDLLOVERRIDES:-"mshtml="}
LOG=$ROOT/logs/install-$PFX
mkdir -p "$LOG"
say() { echo; echo "=== $*"; }

say "0. environment"
echo "prefix=$WINEPREFIX  wine=$WINE  display=$DISPLAY"
[ "$DISPLAY" = ":0" ] && { echo "REFUSING to run on the user's desktop (:0)"; exit 3; }

say "1. prefix"
if [ -f "$WINEPREFIX/system.reg" ]; then
    echo "prefix already exists"
else
    "$WINE" wineboot -u >"$LOG/wineboot.log" 2>&1
    echo "wineboot rc=$?"
fi

say "2. .NET Framework 4.8"
# `reg query` prints the value in hex (0x80eb1 etc.), and bash's `-ge` cannot compare that with a decimal literal —
# it errors, the error was being swallowed, and the test was therefore *always* false: the 40-minute winetricks stage
# ran even on a prefix that already had 4.8. Convert first (A5's from-empty run is what caught this; FINDINGS M35).
rel=$("$WINE" reg query 'HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' /v Release 2>/dev/null | tr -d '\r' | awk '/Release/{print $3}')
rel_dec=$(( ${rel:-0} ))
echo "Release=$rel (${rel_dec})"
# 528040 = .NET Framework 4.8; the app's own requirement is 4.7.2+ (it runs fine on 4.8 — that is what the whole
# project uses), so 4.8 is enough and re-running the 30-60 minute winetricks stage on such a prefix is pure waste.
# (The previous 533320 = 4.8.1 meant "always reinstall", which together with the hex bug above made this stage
# run unconditionally.)
if [ "$rel_dec" -ge 528040 ]; then
    echo "already present (>= 528040, .NET 4.8)"
elif [ "$SKIP_NETFX" = 1 ]; then
    echo "SKIPPED by request (only safe if the app's own WPF/CLR pieces are otherwise satisfied)"
else
    echo "installing via winetricks (long: .NET 4.0 then 4.8; watch $LOG)"
    winetricks -q dotnet48 >"$LOG/dotnet48.log" 2>&1
    echo "winetricks rc=$?"
    rel=$("$WINE" reg query 'HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' /v Release 2>/dev/null | tr -d '\r' | awk '/Release/{print $3}')
    echo "Release now=$rel"
fi

say "3. fonts"
if [ -n "$(ls -A "$FONTS_DIR" 2>/dev/null)" ]; then
    bash "$ROOT/tools/install_fonts.sh" "$PFX" "$FONTS_DIR" | tail -12
else
    echo "no fonts in $FONTS_DIR — WPF will fall back; provision fonts/ from a licensed Windows install"
fi

say "4. WebView2 runtime"
if [ -n "$WEBVIEW2_DIR" ] && [ -d "$WEBVIEW2_DIR" ]; then
    # One implementation: deploy_webview2.sh places the tree, writes the *Windows* form of the loader path and
    # registers the EdgeUpdate client key that Power BI queries. Re-implementing that here is how the first
    # from-empty prefix ended up with a folder named after the source tree, no EdgeUpdate key, and the app stuck on
    # "Installing a required update" (its Evergreen bootstrapper, which cannot run under Wine) instead of rendering
    # — the A5 run caught it (FINDINGS M36).
    if [ -n "$WEBVIEW2_VERSION" ]; then
        bash "$ROOT/tools/deploy_webview2.sh" "$WEBVIEW2_DIR" "$PFX" --version "$WEBVIEW2_VERSION"
    else
        bash "$ROOT/tools/deploy_webview2.sh" "$WEBVIEW2_DIR" "$PFX"
    fi
else
    echo "no --webview2 DIR given: the app will not find a runtime (canvas/start page will fail)"
fi

say "5. install Power BI"
if [ "$USE_BOOTSTRAPPER" = 1 ]; then
    SETUP=/home/asdf/Downloads/PBIDesktopSetup_x64.exe
    echo "bootstrapper: $SETUP"
    # PBI_enableWebView2Install=false: the MSI's WebView2 custom action reads this environment value
    # (SetEnableWebView2Install -> EnableWebView2Install=[%PBI_enableWebView2Install]) and skips the
    # Evergreen installer, which cannot work under Wine. A timeout guards the case where the CA runs anyway and
    # the Edge updater it spawns never exits (that is exactly what happened before — FINDINGS M5).
    PBI_enableWebView2Install=false timeout 2400 "$WINE" "$SETUP" /quiet /norestart ACCEPT_EULA=1 /log "C:\\pbi_boot_$PFX.log" \
        >"$LOG/bootstrapper.log" 2>&1
    rc=$?
    echo "bootstrapper rc=$rc (log: $WINEPREFIX/drive_c/pbi_boot_$PFX.log) [124 = timed out]"
else
    echo "direct MSI: $MSI"
    PBI_enableWebView2Install=false timeout 2400 "$WINE" msiexec /i "$(winepath -w "$MSI" 2>/dev/null || echo "$MSI")" \
        /qn /l*v "C:\\pbi_msi_$PFX.log" ACCEPT_EULA=1 MSIFASTINSTALL=7 >"$LOG/msi.log" 2>&1
    rc=$?
    echo "msiexec rc=$rc (log: $WINEPREFIX/drive_c/pbi_msi_$PFX.log) [124 = timed out]"
fi

say "6. prefix fixups"
bash "$ROOT/tools/pbi_fixups.sh" "$PFX" | tail -12

say "7. result"
EXE="$WINEPREFIX/drive_c/Program Files/Microsoft Power BI Desktop/bin/PBIDesktop.exe"
[ -f "$EXE" ] && echo "PBIDesktop.exe present: $(stat -c%s "$EXE") bytes" || echo "MISSING PBIDesktop.exe"
echo "next: tools/verify.sh $PFX 240"
