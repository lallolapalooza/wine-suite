#!/bin/bash
# Launch Tableau on the WINDOWS guest from the admin-extracted tree, sample frames, collect its logs.
#
#   tools/win_run_tableau.sh <tag> [seconds]
#
# No elevation: the tree at C:\TableauRef comes from `msiexec /a` and runs as the normal user, exactly like
# the Wine run does. Frames are sampled host-side (`virsh screenshot`, one sampler only); the app's own logs
# are pulled through the :8000 hub by tools/collect_logs.sh.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:?usage: win_run_tableau.sh <tag> [seconds]}
SECS=${2:-120}
EXE='C:\TableauRef\Tableau\Tableau 2026.2\bin\tableau.exe'

echo "== clean desktop noise + launch"
"$ROOT/tools/guest.sh" "(New-Object -ComObject Shell.Application).MinimizeAll(); \$p=@(); Get-Process -Name tableau -ErrorAction SilentlyContinue | ForEach-Object { \$p += \$_.Id }; if (\$p.Count) { 'already_running=' + (\$p -join ',') } else { \$q = Start-Process -FilePath '$EXE' -PassThru; 'launched=' + \$q.Id }" 90

echo "== sampling ${SECS}s"
"$ROOT/tools/win_frame_sampler.sh" "$TAG" "$SECS" 5

echo "== app process state"
"$ROOT/tools/guest.sh" "\$p=@(Get-Process -Name tableau -ErrorAction SilentlyContinue); 'alive=' + \$p.Count + ' pids=' + ((\$p | ForEach-Object { \$_.Id }) -join ',') + ' cpu=' + ((\$p | ForEach-Object { [math]::Round(\$_.CPU,1) }) -join ',') + ' title=' + ((\$p | ForEach-Object { \$_.MainWindowTitle }) -join '|')" 60

echo "== collecting logs"
"$ROOT/tools/collect_logs.sh" "$TAG"
