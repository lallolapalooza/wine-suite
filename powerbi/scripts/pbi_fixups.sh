#!/bin/bash
# Prefix fixups that Power BI's stack needs under Wine. Idempotent; safe to re-run.
#
#   tools/pbi_fixups.sh [prefix-name]        # default: pbi
#
# Each fixup states why. Add new ones here (never ad-hoc) so the unattended install can replay them.
set -o pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PFX=${1:-pbi}
source "$ROOT/tools/pbi_env.sh" "$PFX"

say() { echo "== $*"; }
reg() { "$WINE" reg add "$1" /v "$2" /t "${3:-REG_SZ}" /d "$4" /f >/dev/null 2>&1 && echo "   set $1\\$2 = $4" || echo "   FAILED $1\\$2"; }

say "1. WebView2/Chromium arguments: DELIBERATELY NOT SET (measured no-op, M65/M66)"
# WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS does NOT reach Chromium under Wine. Measured, not inferred:
#   * with the value set in HKCU\Environment AND exported into the app's environment, 82 samples of every
#     msedgewebview2.exe command line over a 420 s run show 0 hits for --disable-gpu, 0 for
#     --remote-debugging-port and 0 for CalculateNativeWinOcclusion; the only Chromium switch present is
#     WebView2's own --disable-features=msSmartScreenProtection. CDP never opens: the argument never arrives.
#   * the documented third channel, the policy key
#     HKCU\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments, delivers nothing either — and
#     a 17.9 MB WINEDEBUG=+reg trace shows the runtime opens that policy subtree 197 times and queries
#     UserDataFolder/ReleaseChannels/ChannelSearchKind 98 times each but AdditionalBrowserArguments 0 times:
#     the runtime never asks for the value, so this is not Wine failing to surface it. [INFERENCE] Power BI
#     passes its own arguments (the browser line carries its --js-flags=--max_old_space_size=8192).
# Consequence: any flag written through these channels is a no-op, so this fixup no longer writes one (an
# ineffective line that reads like a fix is worse than no line), and --disable-gpu was never in effect — the
# Windows-identical start page of A3 renders WITHOUT it. Evidence: FINDINGS M65/M66, docs/OCCLUSION.md 3.2.
# Remove the stale value left by older runs of this script, since it can only mislead:
"$WINE" reg delete 'HKCU\Environment' /v WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS /f >/dev/null 2>&1 \
    && echo "   removed stale WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS (was a no-op)" \
    || echo "   WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS already absent"

say "2. Domain/hosts entries the app-internal names resolve through (patch 0006 makes Wine read the hosts file)"
HOSTS="$WINEPREFIX/drive_c/windows/system32/drivers/etc/hosts"
if [ -f "$HOSTS" ]; then
    grep -q 'installed-components.autodesk' "$HOSTS" 2>/dev/null || true   # CAD-specific; kept as an example
    echo "   hosts file: $HOSTS ($(wc -l < "$HOSTS") lines)"
else
    echo "   no hosts file at $HOSTS"
fi

say "3. Report the state the launcher will see"
echo "   WINEDLLOVERRIDES hint: launch the app with  WINEDLLOVERRIDES=\"mshtml=\"  (see FINDINGS M3)"
"$WINE" reg query 'HKCU\Environment' 2>/dev/null | grep -iE 'WEBVIEW2|Environment' | head -5

say "3b. App tracing + the registry the app's own startup expects"
# The app's first-run EULA dialog and the WebView2 runtime check are WebView2 HTML; tracing turns the app's
# own trace log on, which names things like the SplashScreenCreationStage that failed (see FINDINGS M10).
reg 'HKCU\Environment' PBI_forceTracing REG_SZ '1'
# Windows version: leave it at Wine's default. Reporting Windows 10 makes Power BI's WebView2 process *die* under
# Wine — measured, run by run, from the app's own traces (`OnWebViewProcessFailed` counts): with
# `HKCU\Software\Wine\Version = win10` the count is 9-11 and the main window renders solid black (the judge refuses
# it: `verdict BLANK`, `unique=3`, 92 % black), and with the default version the count is 0 and the Windows-identical
# start page renders (A3 PASS). `--disable-gpu` was set through WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS throughout —
# and per §1 that channel never delivers, so the flag was never in effect at all; either way this is not a GPU-flag
# interaction. The default costs a cosmetic difference: Power BI logs
# warningId="DeprecatedOS" and shows a small banner in every view, which the Windows 11 reference does not have.
# Prefer the working UI; revisit only with a real fix for the WebView2 death. Evidence: FINDINGS M29.
# (do NOT add: reg 'HKCU\Software\Wine' Version REG_SZ 'win10')

# Browser-emulation controls the MSI writes (values are strings there, per its Registry table).
reg 'HKLM\SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION' PBIDesktop.exe REG_SZ '11000'
reg 'HKLM\SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_GPU_RENDERING' PBIDesktop.exe REG_SZ '1'
# Culture keys. TYPES MATTER: the MSI's Registry table marks values with a leading '#' as REG_DWORD
# (`SupportsMultiLanguage #1`, `DisableUpdateNotification #1`, `EnableCustomerExperienceProgram #[…]`), and the app
# validates the kind — writing SupportsMultiLanguage as a string makes it die at startup with
# "The registry key Software\Microsoft\Microsoft Power BI Desktop\ value 'SupportMultiLanguage' isn't the expected
# type. Parameter name: valueName" (FINDINGS M18). The MSI also already writes all of these; only fill gaps.
dotnet_kind() { "$WINE" reg query "$1" /v "$2" 2>/dev/null | grep -q "$2" && echo "present" || echo "missing"; }
if [ "$(dotnet_kind 'HKLM\Software\Microsoft\Microsoft Power BI Desktop' SupportsMultiLanguage)" = "missing" ]; then
    reg 'HKLM\Software\Microsoft\Microsoft Power BI Desktop' SupportsMultiLanguage REG_DWORD '1'
else
    echo "   SupportsMultiLanguage already present (not touching its type)"
fi
for v in UICulture DefaultUICulture; do
    if [ "$(dotnet_kind 'HKLM\Software\Microsoft\Microsoft Power BI Desktop' "$v")" = "missing" ]; then
        reg 'HKLM\Software\Microsoft\Microsoft Power BI Desktop' "$v" REG_SZ 'en-US'
    else
        echo "   $v already present"
    fi
done
# WinMetadata: .NET Framework resolves WinRT types (Windows.Storage.StorageFile et al) from
# %SystemRoot%\System32\WinMetadata\*.winmd — Wine ships none, so the guest's copies are copied in if present.
WMDIR="$WINEPREFIX/drive_c/windows/system32/WinMetadata"
if [ -d "$ROOT/vmwinmd" ] && [ -n "$(ls -A "$ROOT/vmwinmd" 2>/dev/null)" ]; then
    mkdir -p "$WMDIR"; cp -f "$ROOT"/vmwinmd/*.winmd "$WMDIR"/ 2>/dev/null
    echo "   WinMetadata: $(ls "$WMDIR" | wc -l) winmd files installed"
else
    echo "   WinMetadata: MISSING (drop the guest's C:\\Windows\\System32\\WinMetadata\\*.winmd into vmwinmd/)"
fi

say "4. WebView2 runtime presence"
WV=$(find "$WINEPREFIX/drive_c" -maxdepth 7 -iname 'msedgewebview2.exe' 2>/dev/null | head -1)
if [ -n "$WV" ]; then echo "   runtime: $WV"; else echo "   MISSING: no msedgewebview2.exe in the prefix yet"; fi
