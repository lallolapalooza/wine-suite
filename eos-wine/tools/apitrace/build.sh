#!/bin/sh
# Build apihook.dll, apitrace.exe and selftest.exe with mingw-w64.
set -e
cd "$(dirname "$0")"
CC=${CC:-x86_64-w64-mingw32-gcc}
LDFLAGS="-Wl,--no-insert-timestamp"
OUT=build
mkdir -p "$OUT"

echo "== apihook.dll"
$CC -O2 -Wall -Wextra -Wno-unused-parameter -shared $LDFLAGS -o "$OUT/apihook.dll" \
    src/apihook.c src/hook_common.S

echo "== apitrace.exe"
$CC -O2 -Wall -Wextra $LDFLAGS -o "$OUT/apitrace.exe" src/apitrace.c -lshell32

echo "== selftest.exe"
$CC -O2 -Wall -Wextra $LDFLAGS -o "$OUT/selftest.exe" src/selftest.c

echo "== lateload.dll"
$CC -O2 -Wall -Wextra -shared $LDFLAGS -o "$OUT/lateload.dll" tests/lateload.c -lwinmm

echo "== ok"
ls -l "$OUT"
