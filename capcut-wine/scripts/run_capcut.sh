#!/bin/bash
# Launch CapCut under Wine, sample screenshots, and collect every log the app writes.
# usage: run_capcut.sh <tag> [seconds] [winedebug] [exe]
#   tag        label for logs/recon output
#   seconds    how long to observe (default 120)
#   winedebug  WINEDEBUG value (default -all)
#   exe        relative exe under the version dir (default CapCut.exe)
set -u
CCWS=/home/asdf/projects/capcut-wine
TAG=${1:-run}
DUR=${2:-120}
DBG=${3:--all}
EXE=${4:-CapCut.exe}
export WINEPREFIX=$CCWS/prefix
export PATH=/opt/wine-staging/bin:$PATH
export DISPLAY=:9
APPDIR="$WINEPREFIX/drive_c/users/asdf/AppData/Local/CapCut/Apps"
VDIR="$APPDIR/9.5.0.4050"
UD="$WINEPREFIX/drive_c/users/asdf/AppData/Local/CapCut/User Data"
OUT="$CCWS/logs/$TAG"; mkdir -p "$OUT" "$CCWS/recon/$TAG"

# clean slate
wineserver -k 2>/dev/null; sleep 4
pkill -f "CapCut.exe" 2>/dev/null; sleep 1
rm -f "$UD/CEF/cef_log.log"

cd "$VDIR" || exit 1
env WINEDEBUG="$DBG" wine "$EXE" > "$OUT/stdout.log" 2>&1 &
WPID=$!
echo "launched pid=$WPID tag=$TAG dur=${DUR}s dbg=$DBG"

start=$(date +%s)
for t in 2 5 10 20 40 60 90 120 180 240 300 420 600; do
  [ "$t" -gt "$DUR" ] && break
  while [ $(( $(date +%s) - start )) -lt "$t" ]; do
    kill -0 $WPID 2>/dev/null || break
    sleep 1
  done
  kill -0 $WPID 2>/dev/null || { echo "PROCESS EXITED at t=${t}s"; break; }
  import -window root "$CCWS/recon/$TAG/${TAG}_${t}s.png" 2>/dev/null
done

alive=$(kill -0 $WPID 2>/dev/null && echo yes || echo no)
echo "alive_at_end=$alive"
# collect app logs
cp -a "$UD/CEF/cef_log.log" "$OUT/" 2>/dev/null
cp -a "$UD/Log/VeDetector_"*.log "$OUT/" 2>/dev/null
cp -a "$UD/Log/alog/log/"*.alog.hot "$OUT/" 2>/dev/null
cp -a "$UD/Crash/"* "$OUT/crash_" 2>/dev/null
cp -a "$UD/VELog/"* "$OUT/" 2>/dev/null
ps -eo pid,ppid,pcpu,pmem,args --sort=-pcpu | grep -i "capcut\|VECreator" | grep -v grep > "$OUT/procs.txt"
echo "collected -> $OUT"
