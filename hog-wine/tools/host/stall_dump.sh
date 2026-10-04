#!/bin/bash
# Capture the Eos post-splash stall: launch with sync tracing + late-ptrace helper,
# then gdb-dump every thread.  usage: stall_dump.sh <tag> [settle_secs]
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT/env.sh"
TAG="${1:-stall1}"; SETTLE="${2:-45}"
D="$EW_LOGS/runs/winedbg/$TAG"; rm -rf "$D"; mkdir -p "$D"
export WINEPREFIX=$(readlink -f "$EW_PREFIX") DISPLAY="$DISP"
APPDIR="$WINEPREFIX/drive_c/Program Files/ETC/EosFamily/v3/Eos"

pkill -9 -x 'Eos.exe' 2>/dev/null; sleep 1
cd "$APPDIR"
LD_PRELOAD="$EW_TMP/late_ptrace.so" WINEDEBUG="+timestamp,+sync,+seh" \
  setsid nohup "$WINEBUILD" ./Eos.exe > "$D/app.stderr" 2>&1 &
P=""
for i in $(seq 1 90); do P=$(pgrep -x 'Eos.exe' | head -1); [ -n "$P" ] && break; sleep 1; done
[ -n "$P" ] || { echo "NO PID"; head -30 "$D/app.stderr"; exit 1; }
echo "pid=$P"
sleep "$SETTLE"
echo "alive=$(ps -o etime= -p "$P" 2>/dev/null || echo DEAD)"
cp "/proc/$P/maps" "$D/maps.txt" 2>/dev/null
{ for t in /proc/$P/task/*; do
    printf "%s comm=%s wchan=%s\n" "$(basename $t)" "$(cat $t/comm 2>/dev/null)" "$(cat $t/wchan 2>/dev/null)"
  done; } > "$D/task_state.txt" 2>&1
echo "threads=$(grep -c . "$D/task_state.txt")"
grep -a 'err:sync' "$D/app.stderr" | tail -20 > "$D/sync_errors.txt"
cat "$D/sync_errors.txt"
gdb -p "$P" -batch -ex 'set pagination off' -ex 'set debuginfod enabled off' \
    -ex 'info threads' -ex 'thread apply all bt' -ex 'detach' \
    > "$D/gdb.txt" 2>&1
echo "gdb rc=$? lines=$(wc -l < "$D/gdb.txt")"
grep -c '^Thread' "$D/gdb.txt" || true
