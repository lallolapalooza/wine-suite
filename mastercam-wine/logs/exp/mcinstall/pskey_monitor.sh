#!/bin/bash
P=/home/asdf/projects/mastercam-wine/state/exp/mcinstall/prefix
W=/home/asdf/projects/resolume-wine/wine-install/bin/wine
export WINEPREFIX="$P"
K='HKLM\Software\Classes\CLSID\{00020420-0000-0000-C000-000000000046}\InprocServer32'
for i in $(seq 1 120); do
  v=$(timeout 20 $W reg query "$K" 2>/dev/null | sed -n '3p' | sed 's/^ *//')
  echo "$(date +%T) [$v]" >> /home/asdf/projects/mastercam-wine/logs/exp/mcinstall/pskey_monitor.log
  sleep 8
done
