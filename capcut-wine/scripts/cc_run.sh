#!/bin/bash
# cc_run.sh -- reliable observer for CapCut under Wine on DISPLAY=:9.
#
# usage: cc_run.sh <tag> [seconds] [winedebug] [exe] [extra_env]
#   tag        label; outputs go to logs/<tag>/ and recon/<tag>/
#   seconds    observation window, default 240
#   winedebug  WINEDEBUG value, default err+all,fixme-all
#   exe        exe name relative to the app version dir, default CapCut.exe
#   extra_env  extra space-separated KEY=VALUE assignments for the app,
#              e.g. "DXVK_LOG_LEVEL=debug DXVK_HUD=devinfo"
#   env        WINELOADER_BIN=/path/to/bin  selects the Wine build to drive
#              (default /opt/wine-staging/bin)
#              CC_DISPLAY=:9|:10           X display to run on (default :9)
#              SAMPLE=<seconds>            sampling interval (default 5)
#              DXVK_CONF=<path|none>       install/remove dxvk.conf next to the exe
#              CC_AUTOCLICK=1              press the cyan button in each root capture
#                                          (first-run "Agree and continue"/"Confirm");
#                                          AUTOCLICK_MAX caps the number of clicks
#              CC_KILL_VEDETECTOR_AT=<s>   SIGKILL only VEDetector.exe at t seconds
#
# Why the old fixed-time sampler was replaced:
#   * The app process appears late (hundreds of MB of DLLs) and its unix argv[0]
#     is a *Windows* path ("C:\...\9.5.0.4050\CapCut.exe"), so process-name
#     matching is unreliable -- detection is by argv substring and by X windows.
#   * Qt keeps the top-level window unmapped until the scene graph has content;
#     importing an unmapped window makes `import` hang, which used to wedge the
#     sampler. Only IsViewable windows are captured.
#   * CapCut leaves unrelated Wine windows (explorer.exe, IME) on the display;
#     "the app is gone" is therefore decided on CapCut-class windows only.
#
# Observer behaviour:
#   * kills the prefix's processes (via /proc/*/environ WINEPREFIX match) and its
#     wineserver, removes stale crash reports / cef log;
#   * launches the app, then polls; the first sample is taken the instant an app
#     process or CapCut X window appears, then every SAMPLE s while it lives;
#   * every sample writes root_<t>s.png, win_<id>_<t>s.png for each *viewable*
#     window, the window tree, each window's geometry/Map State, and the process
#     list to logs/<tag>/timeline.log;
#   * at the end it records the launched process' exit code (wait), when each app
#     process disappeared, and always copies the app's own logs.
set -u
CCWS=/home/asdf/projects/capcut-wine
TAG=${1:-run}
DUR=${2:-240}
DBG=${3:-err+all,fixme-all}
EXE=${4:-CapCut.exe}
EXTRA=${5:-}
SAMPLE=${SAMPLE:-5}
# CC_AUTOCLICK=1 presses the CapCut accent-coloured button in each sample's root
# capture (the first-run "Agree and continue" / env-test "Confirm" dialogs).
AUTOCLICK=${CC_AUTOCLICK:-0}

# ---- wine under test -------------------------------------------------------
export WINEPREFIX=$CCWS/prefix
WINEDIR=${WINELOADER_BIN:-${WINEDIR:-/opt/wine-staging/bin}}
export PATH=$WINEDIR:$PATH
# CC_DISPLAY selects the X display (:9 = Xvfb, no DRI3; :10 = Xwayland, DRI3+Present)
export DISPLAY=${CC_DISPLAY:-:9}
WINE_BIN="$WINEDIR/wine"
[ -x "$WINE_BIN" ] || { echo "no wine at $WINE_BIN"; exit 1; }
WINE_VER=$("$WINE_BIN" --version 2>/dev/null || echo '?')

APPDIR="$WINEPREFIX/drive_c/users/asdf/AppData/Local/CapCut/Apps"
VDIR="$APPDIR/9.5.0.4050"
UD="$WINEPREFIX/drive_c/users/asdf/AppData/Local/CapCut/User Data"
OUT="$CCWS/logs/$TAG"; mkdir -p "$OUT" "$CCWS/recon/$TAG"
TL="$OUT/timeline.log"

# ---- one run at a time -----------------------------------------------------
# Every run kills the prefix's pre-existing processes during clean-up, so two
# overlapping runs kill each other (this happened: "killing pre-existing prefix
# pids: ..." followed by `Killed` in the previous run's driver log). Hold a lock
# for the whole run and refuse to start while another run owns the prefix.
LOCKF="$CCWS/logs/.cc_run.lock"
exec 9>"$LOCKF"
if ! flock -n 9; then
  echo "REFUSING to start: another cc_run.sh owns $WINEPREFIX (lock $LOCKF is held)."
  exit 1
fi
echo "obs_owner_pid=$$ (lock $LOCKF held)"

# ---- helpers ---------------------------------------------------------------
prefix_pids() {   # this prefix's processes, by environment (not by name)
  local p pid cand
  cand=$(ps -eo pid=,comm= 2>/dev/null \
    | awk '$2 ~ /^(wineserver|wine|wine64|wine-preloader|wine64-preloader)$/ || $2 ~ /\.exe$/ || $2 ~ /^parfait/ { print $1 }')
  for pid in $cand; do
    p=/proc/$pid
    [ -r "$p/environ" ] || continue
    if tr '\0' '\n' < "$p/environ" 2>/dev/null | grep -qx "WINEPREFIX=$WINEPREFIX"; then
      echo "$pid"
    fi
  done 2>/dev/null
}

# CapCut-family processes (unix argv substring; argv[0] is a Windows path)
app_pids() {
  ps -eo pid=,ppid=,pcpu=,args= 2>/dev/null \
    | grep -iE 'CapCut\.exe|CapCut-DiffUpgrade|VEDetector|VECreator|VESafeGuard|parfait_crash_handler|VECrashHandler' \
    | grep -vE 'cc_run\.sh|grep -iE' || true
}

all_win_ids() {
  xwininfo -root -tree 2>/dev/null | awk '$1 ~ /^0x[0-9a-fA-F]+$/ { print $1 }'
}

# windows belonging to CapCut / its helper processes
capcut_win_ids() {
  xwininfo -root -tree 2>/dev/null \
    | awk '$1 ~ /^0x[0-9a-fA-F]+$/ && tolower($0) ~ /capcut|vedetector|vecreator|dxgi/ { print $1 }'
}

is_viewable() { xwininfo -id "$1" 2>/dev/null | grep -q 'Map State: IsViewable'; }

map_state() { xwininfo -id "$1" 2>/dev/null | awk -F': ' '/Map State/ {print $2}' | head -1; }

win_geom() {   # prints "absX absY width height"
  xwininfo -id "$1" 2>/dev/null | awk -F': *' '
    /Absolute upper-left X/ {ax=$2}
    /Absolute upper-left Y/ {ay=$2}
    /^  Width/  {w=$2}
    /^  Height/ {h=$2}
    END {print ax, ay, w, h}'
}

# ---- optional dxvk.conf next to the exe (DXVK reads it from the app dir) ----
#   DXVK_CONF=<path>  install that file as $VDIR/dxvk.conf
#   DXVK_CONF=none    remove any dxvk.conf
DXVK_CONF=${DXVK_CONF:-}
VDX="$VDIR/dxvk.conf"
case "$DXVK_CONF" in
  "")        : ;;
  none|off)  rm -f "$VDX"; echo "dxvk.conf: removed";;
  *)         cp -f "$DXVK_CONF" "$VDX" && echo "dxvk.conf: installed from $DXVK_CONF";;
esac

# ---- clean slate -----------------------------------------------------------
echo "=== cc_run tag=$TAG dur=$DUR dbg=$DBG exe=$EXE extra=$EXTRA wine=$WINE_VER ($WINE_BIN) ==="
old="$(prefix_pids)"
if [ -n "$old" ]; then
  echo "killing pre-existing prefix pids: $(echo $old | tr '\n' ' ')"
  kill $old 2>/dev/null; sleep 1; kill -9 $old 2>/dev/null; sleep 1
fi
wineserver -k 2>/dev/null; sleep 3
# Pre-warm the prefix with the wine under test: if the prefix was last stamped by a
# different build, the first launch shows Wine's "configuration is being updated"
# dialog and eats 10-30 s of the observation window (observed in stg_wm_builtin).
echo "wineboot -u pre-warm with $WINE_VER ..."
timeout 120 env WINEDEBUG=-all "$WINE_BIN" wineboot -u >"$OUT/wineboot.log" 2>&1
echo "pre-warm done rc=$?"
# query the DLL overrides now, while the prefix is definitely up (querying after the
# app launch used to race the fresh wineserver and print "Unable to find … key")
OVERRIDES=$(WINEDEBUG=-all "$WINE_BIN" reg query 'HKCU\Software\Wine\DllOverrides' 2>/dev/null | tr -s ' \n' ' ')
rm -rf "$UD/Crash/reports" "$UD/Crash/crash_post_reports" 2>/dev/null
rm -f "$UD/CEF/cef_log.log" 2>/dev/null

# ---- dmp rescuer: copy any .dmp the moment it appears ----------------------
( exec 9>&-   # do not hold the run lock after the main script exits
  end=$(( $(date +%s) + DUR + 90 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    d=$(ls -t "$UD/Crash/reports/"*.dmp 2>/dev/null | head -1)
    if [ -n "$d" ] && [ ! -f "$OUT/crash.dmp.saved" ]; then
      s1=$(stat -c%s "$d" 2>/dev/null || echo 0)
      sleep 3   # wait for the writer to finish: a mid-write dump is unusable
      s2=$(stat -c%s "$d" 2>/dev/null || echo 0)
      if [ "$s1" = "$s2" ] && [ "$s1" -gt 100000 ]; then
        cp "$d" "$OUT/crash.dmp" 2>/dev/null && cp "$d" "$OUT/crash.dmp.saved" 2>/dev/null \
          && echo "saved $(basename "$d") ($s1 bytes, stable) at $(date +%T)" >> "$OUT/rescue.log"
      fi
    fi
    sleep 1
  done ) &
RESCUE=$!

# ---- launch ----------------------------------------------------------------
cd "$VDIR" || { echo "no $VDIR"; exit 1; }
# shellcheck disable=SC2086
env WINEDEBUG="$DBG" $EXTRA "$WINE_BIN" "$EXE" > "$OUT/stdout.log" 2>&1 &
WPID=$!
START=$(date +%s)
: > "$TL"
{
  echo "# cc_run timeline  tag=$TAG"
  echo "# cmd: WINEDEBUG=$DBG $EXTRA $WINE_BIN $EXE   (cwd=$VDIR)"
  echo "# wine: $WINE_BIN ($WINE_VER)  prefix=$WINEPREFIX  display=$DISPLAY"
  echo "# dxvk.conf: ${DXVK_CONF:-<unchanged>} ($( [ -f "$VDX" ] && echo present || echo absent ))"
  echo "# dlloverrides: ${OVERRIDES:-<key absent = Wine builtin defaults>}"
  echo "# launched at $(date -Is) unix=$START  launcher_pid=$WPID"
} >> "$TL"
echo "launched pid=$WPID tag=$TAG dur=${DUR}s dbg=$DBG extra=$EXTRA"

take_sample() {  # $1 = elapsed seconds
  local el=$1 id
  echo "--- t=${el}s wall=$(date +%T) ---" >> "$TL"
  echo "procs:" >> "$TL"
  app_pids >> "$TL"
  echo "capcut-windows (id, MapState, name/class):" >> "$TL"
  for id in $(capcut_win_ids); do
    echo "$id $(map_state "$id") $(xwininfo -id "$id" 2>/dev/null | awk -F'"' '/xwininfo: Window id/ {print $2}')" >> "$TL"
  done
  echo "window-tree:" >> "$TL"
  xwininfo -root -tree >> "$TL" 2>/dev/null
  timeout 15 import -window root "$CCWS/recon/$TAG/root_${el}s.png" 2>/dev/null
  for id in $(all_win_ids); do
    if is_viewable "$id"; then
      timeout 6 import -window "$id" "$CCWS/recon/$TAG/win_${id}_${el}s.png" 2>/dev/null
    fi
  done
  # second root capture: a window can be mapped between the tree dump and the
  # first capture, and Wine windows are frequently (un)mapped by the app
  timeout 15 import -window root "$CCWS/recon/$TAG/root_${el}s_b.png" 2>/dev/null
  # optional: press the CapCut accent-coloured button ("Agree and continue" /
  # "Confirm") that otherwise blocks the first-run flow
  if [ "$AUTOCLICK" = 1 ] && [ "$clicks_used" -lt "${AUTOCLICK_MAX:-6}" ]; then
    local hit x y n id ax ay w h
    hit=$(python3 "$CCWS/scripts/find_cyan_click.py" "$CCWS/recon/$TAG/root_${el}s_b.png" 2>/dev/null || true)
    if [ -n "$hit" ]; then
      x=$(echo "$hit" | awk '{print $1}'); y=$(echo "$hit" | awk '{print $2}'); n=$(echo "$hit" | awk '{print $3}')
      xdotool mousemove "$x" "$y" click 1 2>/dev/null && clicks_used=$(( clicks_used + 1 ))
      echo "CLICK #$clicks_used at t=${el}s -> ($x,$y) run=$n [cyan finder]" | tee -a "$TL"
      sleep 2
    else
      # fallback: a small CapCut dialog (the ToS card is 352x161) -- press its
      # primary button at 45% width / 79% height and then send Return.
      for id in $(capcut_win_ids); do
        is_viewable "$id" || continue
        read -r ax ay w h <<< "$(win_geom "$id")"
        [ -n "${w:-}" ] || continue
        if [ "$w" -le 480 ] && [ "$h" -le 340 ]; then
          x=$(( ax + w * 45 / 100 )); y=$(( ay + h * 79 / 100 ))
          xdotool mousemove "$x" "$y" click 1 2>/dev/null
          xdotool key --clearmodifiers Return 2>/dev/null
          clicks_used=$(( clicks_used + 1 ))
          echo "CLICK #$clicks_used at t=${el}s -> ($x,$y) [dialog $id ${w}x${h} at $ax,$ay + Return]" | tee -a "$TL"
          sleep 2
          break
        fi
      done
    fi
  fi
}

seen_at=""; last_shot=-100; launcher_alive=0; last_seen_procs=0; gone_at=""
clicks_used=0
launcher_was_alive=1
KILL_VED_AT=${CC_KILL_VEDETECTOR_AT:-0}
ved_killed=0
while :; do
  now=$(date +%s); el=$(( now - START ))
  [ "$el" -gt "$DUR" ] && break
  if [ "$KILL_VED_AT" -gt 0 ] && [ "$ved_killed" = 0 ] && [ "$el" -ge "$KILL_VED_AT" ]; then
    vp=$(app_pids | grep -i 'VEDetector' | awk '{print $1}')
    [ -n "$vp" ] && { kill -9 $vp 2>/dev/null; ved_killed=1; \
      echo "KILLED VEDetector at t=${el}s (pids $(echo $vp | tr '\n' ' '))" | tee -a "$TL"; }
  fi
  kill -0 "$WPID" 2>/dev/null && launcher_alive=1 || launcher_alive=0
  if [ "$launcher_alive" = 0 ] && [ "$launcher_was_alive" = 1 ]; then
    echo "LAUNCHER EXITED at t=${el}s wall=$(date +%T) procs_left=$(app_pids | grep -c . || true)" | tee -a "$TL"
    cp -f "$OUT/stdout.log" "$OUT/stdout_at_exit.log" 2>/dev/null
    echo "  (stdout snapshot: $(wc -c < "$OUT/stdout.log" 2>/dev/null) bytes -> stdout_at_exit.log)" >> "$TL"
    launcher_was_alive=0
  fi
  ap="$(app_pids)"; np=$(echo "$ap" | grep -c . || true)
  [ "$np" -gt 0 ] && last_seen_procs=$el
  cw="$(capcut_win_ids)"; ncw=$(echo "$cw" | grep -c . || true)
  if [ -z "$seen_at" ] && { [ "$np" -gt 0 ] || [ "$ncw" -gt 0 ]; }; then
    seen_at=$el
    echo "FIRST SEEN app at t=${el}s (procs=$np capcut_windows=$ncw)" | tee -a "$TL"
  fi
  if [ -n "$seen_at" ] && [ $(( el - last_shot )) -ge "$SAMPLE" ]; then
    take_sample "$el"
    last_shot=$el
    echo "sample t=${el}s procs=$np capcut_windows=$ncw launcher_alive=$launcher_alive" >> "$TL"
  fi
  if [ -n "$seen_at" ] && [ "$launcher_alive" = 0 ] && [ "$np" -eq 0 ] && [ "$ncw" -eq 0 ]; then
    gone_at=$el
    echo "ALL CAPCUT PROCESSES/WINDOWS GONE at t=${el}s" | tee -a "$TL"
    break
  fi
  sleep 1
done

final_el=$(( $(date +%s) - START ))
launcher_alive_end=$(kill -0 "$WPID" 2>/dev/null && echo yes || echo no)
if [ "$launcher_alive_end" = yes ]; then
  take_sample "$final_el"
  echo "final live sample at t=${final_el}s" >> "$TL"
fi
left=$(app_pids | grep -c . || true)
if [ "$launcher_alive_end" = yes ] || [ "$left" -gt 0 ]; then
  wineserver -k 2>/dev/null
fi

wait "$WPID" 2>/dev/null; EC=$?
echo "exit_code=$EC elapsed_at_exit=${final_el}s launcher_alive_at_end=$launcher_alive_end"
{
  echo "exit_code=$EC"
  echo "elapsed_at_exit=$final_el"
  echo "launcher_alive_at_end=$launcher_alive_end"
  echo "last_time_app_proc_seen_s=$last_seen_procs"
  echo "all_capcut_gone_at_s=${gone_at:-n/a}"
  echo "n_app_procs_left=$left"
} >> "$TL"
app_pids > "$OUT/procs_at_exit.txt"

# ---- collect the app's own logs (always) ----------------------------------
sleep 2
cp -a "$UD/CEF/cef_log.log" "$OUT/" 2>/dev/null
cp -a "$UD/Log/VeDetector_"*.log "$OUT/" 2>/dev/null
cp -a "$UD/Log/alog/log/"*.alog.hot "$OUT/" 2>/dev/null
cp -a "$UD/VELog/"*.log "$OUT/" 2>/dev/null
cp -a "$UD/Crash/"* "$OUT/crash_" 2>/dev/null
kill "$RESCUE" 2>/dev/null
echo "collected -> $OUT ; screenshots=$(ls "$CCWS/recon/$TAG" | wc -l)"
