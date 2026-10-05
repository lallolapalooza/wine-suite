#!/bin/bash
# Shared environment for every Wine run in this project. Source it:  source tools/pbi_env.sh [prefix-name]
#
#   WINEPREFIX  = $ROOT/prefix/<prefix-name>   (default: pbi)
#   WINE        = wine-staging 11.18 (/opt/wine-staging/bin/wine), our fork overlay if built
#   DISPLAY     = :9 Xvfb session (tools/host/xvfb9.sh) or the VNC display :2, whichever you set
#
# Rationale: the distro's `wine` (10.0) is NOT what we test with; the staging 11.18 tree is, and
# wine/install/bin/wine (our patched fork) overrides it when present.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PFX=${1:-${PFX:-pbi}}

export PROJECT_ROOT=$ROOT
export WINEPREFIX=$ROOT/prefix/$PFX
export WINEARCH=win64
export WINEDEBUG=${WINEDEBUG:--all}

# Prefer our patched fork, but only once its install has actually completed: `bin/wine` appears early *during*
# `make install`, and a half-installed tree fails with "could not load ntdll.so". PBIFORK=0 forces stock staging
# (useful for A/B comparisons), PBIFORK=1 demands the fork and fails loudly if it is not usable.
fork_ready() { [ -x "$ROOT/wine/install/bin/wine" ] && [ -f "$ROOT/wine/install/.wine-build-complete" ]; }
case "${PBIFORK:-auto}" in
    0)
        export WINE=/opt/wine-staging/bin/wine
        export WINEFORK=0
        ;;
    1)
        if fork_ready; then
            export WINE="$ROOT/wine/install/bin/wine"
            export WINEFORK=1
        else
            echo "PBIFORK=1 requested but $ROOT/wine/install/bin/wine is not installed/complete" >&2
            return 4 2>/dev/null || exit 4
        fi
        ;;
    *)
        if fork_ready; then
            export WINE="$ROOT/wine/install/bin/wine"
            export WINEFORK=1
        else
            export WINE=/opt/wine-staging/bin/wine
            export WINEFORK=0
        fi
        ;;
esac
export PATH=/opt/wine-staging/bin:$PATH

# Wine GUI apps need an X display. Default to the VNC session (:2) because it has a window manager (openbox):
# Power BI's main window is *maximised* on Windows, and with no WM the maximise request is simply lost, so the
# geometry cannot match. :2 also lets the user watch a run live. PBIDISPLAY=:9 gives the hermetic headless Xvfb.
# NEVER :0 — an inherited DISPLAY=:0 is how stray installers ended up painting dialogs on the user's desktop.
export DISPLAY=${PBIDISPLAY:-:2}

wine_run() { "$WINE" "$@"; }
mkdir -p "$WINEPREFIX" "$ROOT/logs"
