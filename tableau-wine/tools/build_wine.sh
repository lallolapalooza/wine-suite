#!/bin/bash
# Build the project Wine fork (Wine 11.18 + the CAD patch series) into wine/install.
# Idempotent: skips configure/make when already done. Safe to re-run after adding a patch
# (make picks the change up).
#
#   JOBS=14 tools/build_wine.sh            # configure (once) + build + install
#   tools/build_wine.sh --check            # verify the tree/prefix state, build nothing
#
# Logs: logs/wine-build.log (appended). Source tree: wine/wine-11.18. Output: wine/install.
set -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$ROOT/wine/wine-11.18
PREFIX=$ROOT/wine/install
LOG=$ROOT/logs/wine-build.log
# Job count matters here, not just for speed: a Wine compile job is ~1.5-2 GB of RSS (some C++ translation units
# are worse), and this host has 30 GB with ~12 GB already in use by the Windows VM and Wine sessions. 14 jobs
# OOM-killed the build. Keep total RAM under ~90 %: 6 jobs is ~12 GB of compilers with room to spare.
JOBS=${JOBS:-6}
mkdir -p "$ROOT/logs"

check() {
    echo "source : $SRC $( [ -d "$SRC" ] && echo present || echo MISSING )"
    echo "prefix : $PREFIX"
    test -x "$PREFIX/bin/wine" && "$PREFIX/bin/wine" --version 2>/dev/null || echo "  (no wine binary yet)"
    test -f "$SRC/Makefile" && echo "configured: yes" || echo "configured: no"
    test -f "$SRC/dlls/ntdll/x86_64-windows/ntdll.dll" && echo "x86_64 built: yes" || echo "x86_64 built: no"
    test -f "$SRC/dlls/ntdll/i386-windows/ntdll.dll" && echo "i386 built: yes" || echo "i386 built: no"
}

if [ "$1" = "--check" ]; then check; exit 0; fi

cd "$SRC" || { echo "no source tree at $SRC"; exit 1; }

if [ ! -f Makefile ]; then
    echo "== configure ==" | tee -a "$LOG"
    ./configure --prefix="$PREFIX" --enable-archs=i386,x86_64 --disable-tests \
        >>"$LOG" 2>&1 || { echo "configure FAILED (tail):"; tail -30 "$LOG"; exit 1; }
fi

echo "== make -j$JOBS $(date -Is) ==" | tee -a "$LOG"
make -j"$JOBS" >>"$LOG" 2>&1
rc=$?
echo "== make rc=$rc $(date -Is) ==" | tee -a "$LOG"
[ $rc -ne 0 ] && { echo "make FAILED, last lines:"; tail -40 "$LOG"; exit $rc; }

echo "== make install $(date -Is) ==" | tee -a "$LOG"
make install >>"$LOG" 2>&1 || { echo "make install FAILED:"; tail -30 "$LOG"; exit 1; }
"$PREFIX/bin/wine" --version
# Completion marker: `bin/wine` appears early *during* `make install`, so chaining on its existence fires too
# soon (the Unix libs land later and wine then fails with "could not load ntdll.so"). Wait for this file instead.
touch "$PREFIX/.wine-build-complete"
echo "OK: $PREFIX/bin/wine (marker: $PREFIX/.wine-build-complete)"
