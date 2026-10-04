#!/bin/bash
export WINEPREFIX=/run/media/asdf/Windows/mc-scratch/pfx2
W=/home/asdf/projects/mastercam-wine/wine-install/bin/wine
L=/home/asdf/projects/mastercam-wine/logs/exp/mcinstall/keymon3.log
for i in $(seq 1 200); do
  v=$(timeout 15 $W reg query 'HKLM\Software\Classes\CLSID\{00020420-0000-0000-C000-000000000046}\InprocServer32' 2>/dev/null | sed -n '3p' | sed 's/^ *//')
  echo "$(date +%T) [$v]" >> $L
  sleep 6
done
