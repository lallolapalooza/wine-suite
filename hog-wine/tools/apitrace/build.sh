#!/bin/sh
# Build apihook.dll, apitrace.exe and selftest.exe with mingw-w64.
set -e
cd "$(dirname "$0")"
CC=${CC:-x86_64-w64-mingw32-gcc}
LDFLAGS="-Wl,--no-insert-timestamp"
OUT=${OUT:-build}
# The trampoline is architecture specific: hook_common.S is Win64, hook_common32.S
# is Win32 (i386).  Build the 32-bit tracer for 32-bit targets (e.g. Hog PC) with
#   CC=i686-w64-mingw32-gcc OUT=build32 ./build.sh
ASM=src/hook_common.S
case "$CC" in *i686*) ASM=src/hook_common32.S ;; esac
mkdir -p "$OUT"

echo "== apihook.dll ($CC, $ASM)"
$CC -O2 -Wall -Wextra -Wno-unused-parameter -shared $LDFLAGS -o "$OUT/apihook.dll" \
    src/apihook.c "$ASM"

echo "== apitrace.exe"
$CC -O2 -Wall -Wextra $LDFLAGS -o "$OUT/apitrace.exe" src/apitrace.c -lshell32

echo "== selftest.exe"
$CC -O2 -Wall -Wextra $LDFLAGS -o "$OUT/selftest.exe" src/selftest.c

echo "== lateload.dll"
$CC -O2 -Wall -Wextra -shared $LDFLAGS -o "$OUT/lateload.dll" tests/lateload.c -lwinmm

echo "== ok"
ls -l "$OUT"
