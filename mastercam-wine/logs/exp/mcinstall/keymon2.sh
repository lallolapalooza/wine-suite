#!/bin/bash
export WINEPREFIX=/run/media/user/Windows/mc-scratch/pfx-clean
W=/home/user/projects/resolume-wine/wine-install/bin/wine
L=/home/user/projects/mastercam-wine/logs/exp/mcinstall/keymon2.log
K='HKLM\Software\Classes\CLSID\{00020420-0000-0000-C000-000000000046}\InprocServer32'
for i in $(seq 1 200); do v=$(timeout 15 $W reg query "$K" 2>/dev/null | sed -n '3p' | sed 's/^ *//'); echo "$(date +%T) [$v]" >> $L; sleep 6; done
