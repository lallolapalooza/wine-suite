#!/bin/bash
# Run the GetUserNameExW probe (tools/winapi/nameprobe.c) under Wine in the two DNS-domain states the call
# depends on, and write the captures into logs/secur32/.  Two Wine installs are used so the same probe is
# measured before and after the fix that answers NameUserPrincipal/NameDnsDomain:
#
#   before  wine/install-clean   pristine secur32 + patches 0001..0004 (no GetUserNameExW change)
#   after   wine/install         the fork (patches/0001..0005 applied to pristine 11.18)
#
# Wine's wineboot syncs Tcpip\Parameters\Domain from the host's canonical name on each launch (empty on a host
# whose hostname carries no domain suffix), so the "domain" state is set inside the same Wine session as the
# probe - exactly the value a domain-joined Windows machine has.
#
# usage: tools/winapi/run_nameprobe.sh [prefix]        default prefix/nameprobe, display $PROBE_DISPLAY or :9
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PREFIX=${1:-$ROOT/prefix/nameprobe}
DISP=${PROBE_DISPLAY:-:9}
DOMAIN=${DOMAIN:-corp.example.com}
OUT=$ROOT/logs/secur32
EXE=$ROOT/tools/winapi/bin/nameprobe.exe
REG="reg add HKLM\\System\\CurrentControlSet\\Services\\Tcpip\\Parameters /v Domain /t REG_SZ /d $DOMAIN /f"

mkdir -p "$OUT" "$PREFIX/drive_c/winapi"
x86_64-w64-mingw32-gcc -O1 -Wall -o "$EXE" "$ROOT/tools/winapi/nameprobe.c" -ladvapi32 || exit 1
cp "$EXE" "$PREFIX/drive_c/winapi/"

export DISPLAY=$DISP WINEPREFIX=$PREFIX WINEDEBUG=-all

# start from a prefix that exists (wineboot is a no-op when it already does)
"$ROOT/wine/install/bin/wine" wineboot -u >/dev/null 2>&1

run() {   # run <install> <label> <same-session-reg-add?>
    local install=$1 label=$2 with_domain=$3
    {
        if [ "$with_domain" = yes ]; then
            echo "# [Tcpip\\\\Parameters\\\\Domain = $DOMAIN, set in the same Wine session - wineboot resets it"
            echo "#  from the host's canonical name on each launch, which has no domain suffix here]"
        else
            echo "# [no DNS domain: Tcpip\\\\Parameters\\\\Domain empty, the state every prefix on this host has]"
        fi
        echo "# wine: $("$ROOT/wine/$install/bin/wine" --version)  secur32.dll md5: $(md5sum "$ROOT/wine/$install/lib/wine/x86_64-windows/secur32.dll" | cut -d' ' -f1)"
        if [ "$with_domain" = yes ]; then
            "$ROOT/wine/$install/bin/wine" cmd /c "$REG >nul && C:\\winapi\\nameprobe.exe"
        else
            "$ROOT/wine/$install/bin/wine" ./nameprobe.exe
        fi
    } >"$OUT/nameprobe_wine_$label.txt" 2>&1
    echo "wrote $OUT/nameprobe_wine_$label.txt"
}

cd "$PREFIX/drive_c/winapi" || exit 1
run install-clean before_nodomain no
run install       after_nodomain  no
run install-clean before_domain   yes
run install       after_domain    yes
