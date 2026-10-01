#!/bin/bash
# Run the Wine test-suite programs that cover the patch series in patches/ against the fork's build.
#
#   scripts/run_wine_tests.sh                      # wine/build + wine/testprefix
#   WINEPREFIX=/tmp/pfx scripts/run_wine_tests.sh  # another prefix
#
# The programs come from Wine's own test suite (dlls/wintypes/tests, dlls/secur32/tests, dlls/ntdll/tests,
# dlls/oledb32/tests) and each one exercises a patch in the series; without the patch it fails, which is the
# point of running them here.  The prefix is created and booted once, and the WinRT metadata the wintypes
# tests resolve against is staged into it from vmwinmd/ (the same set pbi_fixups.sh deploys into a Power BI
# prefix) - without it those tests skip themselves.
#
# Requires a build of wine/wine-11.18 with tests enabled (configure without --disable-tests):
#   cd wine/build && ../wine-11.18/configure --enable-archs=x86_64 --prefix="$PWD/../install" && make -j
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# The fork: this tree, or another checkout of powerbi/ given through WINESRC
SRC=${WINESRC:-$ROOT/wine/wine-11.18}
[ -x "$SRC/tools/runtest" ] || { echo "no Wine source at $SRC (set WINESRC=<path>/wine/wine-11.18)"; exit 2; }
# Either a separate build directory or the in-tree build the README describes
if [ -z "${WINEBUILD:-}" ]; then
    if [ -f "$ROOT/wine/build/server/wineserver" ]; then BUILD=$ROOT/wine/build
    elif [ -f "$SRC/server/wineserver" ]; then BUILD=$SRC
    else BUILD=$ROOT/wine/build
    fi
else
    BUILD=$WINEBUILD
fi
export WINEPREFIX=${WINEPREFIX:-$ROOT/wine/testprefix}
export WINEDEBUG=${WINEDEBUG:--all}

# module (TESTDLL) -> test program under the build directory
TESTS="
wintypes.dll dlls/wintypes/tests/x86_64-windows/wintypes_test.exe wintypes
secur32.dll  dlls/secur32/tests/x86_64-windows/secur32_test.exe  secur32
secur32.dll  dlls/secur32/tests/x86_64-windows/secur32_test.exe  negotiate
ntdll.dll    dlls/ntdll/tests/x86_64-windows/ntdll_test.exe      impersonate
oledb32.dll  dlls/oledb32/tests/x86_64-windows/oledb32_test.exe  convert
"

[ -f "$BUILD/server/wineserver" ] || { echo "no wine build at $BUILD - see the header of this script"; exit 2; }
[ -x "$BUILD/wine" ] || { echo "no wine launcher at $BUILD/wine"; exit 2; }

if [ ! -d "$WINEPREFIX/drive_c" ]; then
    echo "== creating the prefix $WINEPREFIX =="
    (cd "$BUILD" && ./wine wineboot -u) || exit 1
fi

# The WinRT metadata the resolution tests read (%SystemRoot%\System32\WinMetadata).  Wine's own winmd set
# (Wine builds a handful) is not enough for the namespace and type names the tests use, so the guest's set is
# copied over it - the same files pbi_fixups.sh deploys into a Power BI prefix.  VMWINMD overrides the source.
metadata="$WINEPREFIX/drive_c/windows/system32/WinMetadata"
for dir in "${VMWINMD:-}" "$ROOT/vmwinmd" "$ROOT/../powerbi-linux/vmwinmd"; do
    [ -n "$dir" ] && ls "$dir"/*.winmd >/dev/null 2>&1 && { src=$dir; break; }
done
if [ -n "${src:-}" ]; then
    mkdir -p "$metadata" && cp "$src"/*.winmd "$metadata"/ \
        && echo "== staged $(ls "$metadata" | wc -l) metadata files into $metadata (from $src) =="
else
    echo "== no vmwinmd/*.winmd found (set VMWINMD=<dir>): the resolution tests that need them will skip =="
fi

cd "$BUILD" || exit 1
echo "$TESTS" | while read -r module program name; do
    [ -n "${module:-}" ] || continue
    printf '\n==== %s: %s ====\n' "$program" "$name"
    if ! "$SRC/tools/runtest" -T "$BUILD" -M "$module" -p "$program" "$name"; then
        echo "FAILED: $program $name"
        touch "$BUILD/.wine-tests-failed"
    fi
done
[ -f "$BUILD/.wine-tests-failed" ] && { rm -f "$BUILD/.wine-tests-failed"; echo "RESULT: FAIL"; exit 1; }
echo "RESULT: PASS"
