#!/bin/bash
# =============================================================================
# tools/build_tableau.sh - build the patched Wine fork (wine-11.18/, in place)
#                          and install it into wine-install/
#
#   tools/build_tableau.sh                 # configure (once) + make + make install
#   JOBS=6 tools/build_tableau.sh          # explicit parallelism (default 6)
#   tools/build_tableau.sh --check         # state only, build nothing
#   tools/build_tableau.sh --inc           # incremental make + install, no configure
#   tools/build_tableau.sh --configure-only
#
# Memory: ALWAYS run tools/mem_guard.sh alongside (supervised). 22 jobs OOM-killed prior
# sessions on this host; a Wine compile job is ~1.5-2 GB RSS and the Windows VM holds 8 GB.
# Disk: the tree is built in place (no second copy) because `/` has ~25 GB free.
# Logs: logs/wine-build.log (appended).
# =============================================================================
set -o pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$ROOT/wine-11.18
PREFIX=${WINE_INSTALL:-$ROOT/wine-install}
LOG=$ROOT/logs/wine-build.log
JOBS=${JOBS:-6}
MODE=${1:-}
mkdir -p "$ROOT/logs"

check() {
    echo "source    : $SRC $( [ -d "$SRC" ] && echo present || echo MISSING )"
    echo "prefix    : $PREFIX"
    echo "configured: $( [ -f "$SRC/Makefile" ] && echo yes || echo no )"
    echo "x86_64 dll: $( [ -f "$SRC/dlls/ntdll/x86_64-windows/ntdll.dll" ] && echo built || echo no )"
    echo "i386 dll  : $( [ -f "$SRC/dlls/ntdll/i386-windows/ntdll.dll" ] && echo built || echo no )"
    echo "installed : $( [ -x "$PREFIX/bin/wine" ] && "$PREFIX/bin/wine" --version 2>/dev/null || echo no )"
    echo "free /    : $(df -h / | awk 'NR==2{print $4}')"
    echo "mem avail : $(free -g | awk '/^Mem:/{print $7"GiB"}')"
}

case "$MODE" in
  --check) check; exit 0 ;;
esac

[ -f "$SRC/configure" ] || { echo "no source tree at $SRC (run the patch-union step first)"; exit 1; }
cd "$SRC" || exit 1

if [ "$MODE" != "--inc" ] && [ ! -f Makefile ]; then
    echo "== configure $(date -Is) ==" | tee -a "$LOG"
    ./configure --prefix="$PREFIX" --enable-archs=i386,x86_64 --disable-tests >>"$LOG" 2>&1 \
        || { echo "configure FAILED (tail):"; tail -40 "$LOG"; exit 1; }
fi
[ "$MODE" = "--configure-only" ] && { echo "configure done"; exit 0; }

echo "== make -j$JOBS $(date -Is) ==" | tee -a "$LOG"
avail=$(awk '/^MemAvailable:/{printf "%d", $2/1048576}' /proc/meminfo)
echo "   MemAvailable=${avail}GiB, mem_guard should be running" | tee -a "$LOG"
make -j"$JOBS" >>"$LOG" 2>&1
rc=$?
echo "== make rc=$rc $(date -Is) ==" | tee -a "$LOG"
[ $rc -ne 0 ] && { echo "make FAILED, last lines:"; tail -40 "$LOG"; exit $rc; }

echo "== make install $(date -Is) ==" | tee -a "$LOG"
make install >>"$LOG" 2>&1 || { echo "make install FAILED:"; tail -30 "$LOG"; exit 1; }
"$PREFIX/bin/wine" --version
# bin/wine appears early during `make install`; the Unix libs land later. Marker = really complete.
touch "$PREFIX/.wine-build-complete"
echo "OK: $PREFIX/bin/wine (marker: $PREFIX/.wine-build-complete)"
