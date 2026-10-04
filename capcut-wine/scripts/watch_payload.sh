#!/bin/bash
# Wait for the CapCut stub's payload download inside the wine prefix to finish,
# then copy it to work/payload/ and hash it.
set -u
CCWS=/home/asdf/projects/capcut-wine
LOG=$CCWS/prefix/drive_c/users/asdf/AppData/Local/Temp/installer_downloader.log
CACHE=$CCWS/prefix/drive_c/users/asdf/AppData/Local/app_shell_cache_562354
mkdir -p "$CCWS/work/payload"
last=0
stable=0
for i in $(seq 1 2400); do   # up to 2h at 3s
  f=$(ls -S "$CACHE"/*.exe 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    s=$(stat -c %s "$f" 2>/dev/null || echo 0)
    if [ "$s" = "$last" ]; then stable=$((stable+1)); else stable=0; fi
    last=$s
    if grep -q "Downloader download finish" "$LOG" 2>/dev/null || [ "$stable" -ge 20 ]; then
      cp "$f" "$CCWS/work/payload/app_package.exe"
      sha256sum "$CCWS/work/payload/app_package.exe" > "$CCWS/work/payload/app_package.sha256"
      echo "DONE size=$s stable=$stable" > "$CCWS/work/payload/.download_complete"
      echo "copied $f ($s bytes)"
      exit 0
    fi
  fi
  sleep 3
done
echo "TIMEOUT" > "$CCWS/work/payload/.download_timeout"
