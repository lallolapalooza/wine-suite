#!/bin/bash
# Regenerate the Wine patch series: patches-draft/orig (pristine) vs wine-src (patched).
set -e
WD="$(cd "$(dirname "$0")/.." && pwd)"
ORIG="$WD/patches-draft/orig"
SRC="$WD/wine-src"
OUT="$WD/patches"
mkdir -p "$OUT"

diff_one() {  # path
    local p="$1"
    if [ -f "$ORIG/$p" ]; then
        diff -u --label "a/$p" --label "b/$p" "$ORIG/$p" "$SRC/$p" || true
    else
        diff -u --label "a/$p" --label "b/$p" /dev/null "$SRC/$p" || true
    fi
}

{
    echo "From: omp <omp@localhost>"
    echo "Subject: [PATCH 1/3] win32u: Let the application draw a dark menu bar"
    echo
    echo "Windows 10 1809+ sends the undocumented UAH messages (WM_UAHDRAWMENU /"
    echo "WM_UAHDRAWMENUITEM) to windows that use dark mode, letting the application"
    echo "paint the menu bar itself. Notepad++ 8.x relies on this to theme its menu bar."
    echo
    echo "A window is considered dark when the __wine_dark_mode property is set, which"
    echo "is done by uxtheme's AllowDarkModeForWindow and by dwmapi's"
    echo "DWMWA_USE_IMMERSIVE_DARK_MODE attribute."
    echo "---"
    diff_one dlls/win32u/menu.c
} > "$OUT/0001-win32u-Send-UAH-menu-bar-messages.patch"

{
    echo "From: omp <omp@localhost>"
    echo "Subject: [PATCH 2/3] uxtheme: Implement the undocumented dark mode entry points"
    echo
    echo "AllowDarkModeForWindow/IsDarkModeAllowedForWindow now track a per-window flag,"
    echo "and SetPreferredAppMode(ForceDark) marks the existing windows of the process,"
    echo "instead of being no-op stubs that report failure."
    echo "---"
    diff_one dlls/uxtheme/system.c
} > "$OUT/0002-uxtheme-Implement-dark-mode-entry-points.patch"

{
    echo "From: omp <omp@localhost>"
    echo "Subject: [PATCH 3/3] dwmapi: Implement the DWMWA_USE_IMMERSIVE_DARK_MODE attribute"
    echo
    echo "Store the immersive dark mode state per window instead of ignoring it, so that"
    echo "applications using the documented DWM attribute (Notepad++ on Windows 10 2004+)"
    echo "get dark decorations and a dark menu bar."
    echo "---"
    diff_one dlls/dwmapi/dwmapi_main.c
} > "$OUT/0003-dwmapi-Implement-immersive-dark-mode.patch"

wc -l "$OUT"/*.patch
