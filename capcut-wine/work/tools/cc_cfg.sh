#!/bin/bash
# cc_cfg.sh {hw|sw|show|save <name>|load <name>}
# Switch CapCut's environment-detection config between the two measured states:
#   hw = Wine's own detection result  (hardwareRenderEnable=true,  EnvDetect hw_render=1)
#   sw = Windows reference detection  (hardwareRenderEnable=false, EnvDetect hw_render=0)
# The app rewrites all of these while it runs, so the state must be (re)applied
# immediately before every launch.  Extra files can be added with:
#   CC_CFG_EXTRA="EnvDetectSimulate.json"   (default: all four)
set -eu
CCWS=/home/asdf/projects/capcut-wine
UD="$CCWS/prefix/drive_c/users/asdf/AppData/Local/CapCut/User Data/Config"
SAVED="$CCWS/work/cfgsnap"
FILES="EnvDetect.json EnvDetectSimulate.json ve_hw_check.ini"
case "${1:-show}" in
hw)
  cp -a "$CCWS/recon/config_wine_backup/globalSetting" "$UD/globalSetting"
  for f in $FILES; do cp -a "$CCWS/recon/config_wine_backup/$f" "$UD/$f"; done
  ;;
sw)
  # Windows values from the guest capture
  cp -a "$CCWS/recon/winlog/Config/EnvDetect.json" "$UD/EnvDetect.json"
  cp -a "$CCWS/recon/winlog/Config/EnvDetectSimulate.json" "$UD/EnvDetectSimulate.json"
  cp -a "$CCWS/recon/winlog/Config/ve_hw_check.ini" "$UD/ve_hw_check.ini"
  # globalSetting: take the Windows flags but keep Wine's own cache paths
  python3 - "$UD/globalSetting" "$CCWS/recon/winlog/Config/globalSetting" <<'PY'
import sys, re
cur, win = sys.argv[1], sys.argv[2]
def parse(p):
    d={}
    for line in open(p, encoding='utf-8', errors='replace'):
        line=line.rstrip('\n')
        if line.startswith('['): d.setdefault('__sections__',[]).append(line); continue
        if '=' in line:
            k,v=line.split('=',1); d[k]=v
        elif line.strip(): d.setdefault('__bare__',[]).append(line)
    return d
c=parse(cur); w=parse(win)
for k in ('hardwareRenderEnable','hardwareRenderForbid','prerenderEnable',
          'renderIndexTrackModeDefault','default_enable_cbr','renderIndexTrackModeUserHasModify') :
    if k in w: c[k]=w[k]
out=[]
emitted=set()
for line in open(cur, encoding='utf-8', errors='replace'):
    if '=' in line and not line.startswith('['):
        k=line.split('=',1)[0]
        if k in c: out.append(f"{k}={c[k]}\n"); emitted.add(k); continue
    out.append(line)
for k,v in c.items():
    if k not in emitted and not k.startswith('__') and k not in ('hardwareRenderEnable','hardwareRenderForbid','prerenderEnable','renderIndexTrackModeDefault','default_enable_cbr','renderIndexTrackModeUserHasModify'):
        pass
open(cur,'w').writelines(out)
PY
  ;;
show)
  echo "== globalSetting hw keys =="
  grep -E "hardwareRender|prerenderEnable|renderIndexTrackModeDefault|default_enable_cbr" "$UD/globalSetting" || true
  echo "== EnvDetect.json sizes/mtimes =="
  ls -la "$UD"/EnvDetect*.json "$UD"/ve_hw_check.ini
  python3 -c "import json,sys;print('Qt6Render:',json.load(open('$UD/EnvDetect.json')).get('Qt6RenderEnvironment',{}).get('result'))" 2>/dev/null || echo "(EnvDetect.json unreadable)"
  ;;
save)
  n=${2:?name}
  mkdir -p "$SAVED/$n"; cp -a "$UD"/. "$SAVED/$n"/
  echo "saved -> $SAVED/$n";;
load)
  n=${2:?name}
  cp -a "$SAVED/$n"/. "$UD"/
  echo "loaded <- $SAVED/$n";;
*) echo "usage: $0 {hw|sw|show|save <name>|load <name>}"; exit 1;;
esac
