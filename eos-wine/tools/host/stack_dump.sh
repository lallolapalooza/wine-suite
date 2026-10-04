#!/bin/bash
# Launch Eos, wait for the stall, then gdb-dump per-thread: TEB ClientId (wine tid),
# rsp and a raw stack window.  usage: stack_dump.sh <tag> [settle]
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT/env.sh"
TAG="${1:-stacks1}"; SETTLE="${2:-45}"
D="$EW_LOGS/runs/winedbg/$TAG"; rm -rf "$D"; mkdir -p "$D"
export WINEPREFIX=$(readlink -f "$EW_PREFIX") DISPLAY="$DISP"
APPDIR="$WINEPREFIX/drive_c/Program Files/ETC/EosFamily/v3/Eos"

pkill -9 -x 'Eos.exe' 2>/dev/null; sleep 1
cd "$APPDIR"
LD_PRELOAD="$EW_TMP/late_ptrace.so" WINEDEBUG="+timestamp,+sync,+seh" \
  setsid nohup "$WINEBUILD" ./Eos.exe > "$D/app.stderr" 2>&1 &
P=""
for i in $(seq 1 90); do P=$(pgrep -x 'Eos.exe' | head -1); [ -n "$P" ] && break; sleep 1; done
[ -n "$P" ] || { echo "NO PID"; exit 1; }
echo "unix pid=$P"
sleep "$SETTLE"
grep -a 'err:sync' "$D/app.stderr" | tail -25 > "$D/sync_errors.txt"
cat "$D/sync_errors.txt"
cp "/proc/$P/maps" "$D/maps.txt"
{ for t in /proc/$P/task/*; do
    printf "%s comm=%s wchan=%s\n" "$(basename $t)" "$(cat $t/comm 2>/dev/null)" "$(cat $t/wchan 2>/dev/null)"
  done; } > "$D/task_state.txt" 2>&1
cat > "$D/gdb.cmds" <<'EOF'
set pagination off
set debuginfod enabled off
thread apply all p/x *(unsigned long*)($gs_base+0x48)
thread apply all p/x $rsp
thread apply all x/220gx $rsp
EOF
gdb -p "$P" -batch -x "$D/gdb.cmds" -ex detach > "$D/gdb_raw.txt" 2>&1
echo "gdb rc=$? lines=$(wc -l < "$D/gdb_raw.txt")"
