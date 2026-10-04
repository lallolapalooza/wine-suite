#!/bin/bash
# A/B rig: build the tree WITHOUT the dcomp patch set, install it to a separate DESTDIR, so the
# "blank window" claim can be tested against the real thing instead of argued.
#
#   tools/ab_dcomp.sh revert    # reverse the 67 patches, rebuild, install into state/nodcomp
#   tools/ab_dcomp.sh restore   # re-apply them, rebuild, install back into wine-install
#
# The running wine-install is never touched by the revert leg (DESTDIR keeps the install elsewhere).
set -euo pipefail
CW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$CW/env.sh"
BUILD=$CW/wine/wine-11.18
NODCOMP=$CW/state/nodcomp
export TMPDIR=$CW_TMP

patches() { ls "$CW"/patches/local/dcomp-staging/[0-9]*.patch | sort; }
patches_rev() { patches | tac; }

case "${1:-}" in
revert)
  cd "$BUILD"
  echo "-- reversing $(patches | wc -l) dcomp patches"
  for p in $(patches_rev); do
    patch -p1 --reverse -i "$p" >/dev/null 2>&1 || echo "REVERSE-FAIL $(basename "$p")"
  done
  echo "-- regenerating server protocol (removes the dcomp @REQ entries)"
  ./tools/make_requests server/protocol.def
  grep -c "dcomp" include/wine/server_protocol.h || true
  echo "-- make"
  make -j"${JOBS:-17}" > "$CW/logs/build_nodcomp.log" 2>&1 || { grep -E "error:" "$CW/logs/build_nodcomp.log" | head; exit 1; }
  echo "-- make install DESTDIR=$NODCOMP"
  rm -rf "$NODCOMP"
  make install DESTDIR="$NODCOMP" > "$CW/logs/install_nodcomp.log" 2>&1
  W="$NODCOMP$CW_INSTALL/bin/wine"
  echo "nodcomp wine: $W"
  ls -la "$NODCOMP$CW_INSTALL/lib/wine/x86_64-windows/dcomp.dll" 2>&1 | sed 's/^/  /'
  "$W" --version
  ;;
restore)
  cd "$BUILD"
  echo "-- re-applying dcomp patches"
  for p in $(patches); do
    patch -p1 --forward -i "$p" >/dev/null 2>&1 || echo "APPLY-FAIL $(basename "$p")"
  done
  ./tools/make_requests server/protocol.def
  echo "-- make"
  make -j"${JOBS:-17}" > "$CW/logs/build_redcomp.log" 2>&1 || { grep -E "error:" "$CW/logs/build_redcomp.log" | head; exit 1; }
  echo "-- make install"
  make install > "$CW/logs/install_redcomp.log" 2>&1
  ls -la "$CW_INSTALL/lib/wine/x86_64-windows/dcomp.dll"
  ;;
*)
  echo "usage: $0 revert|restore"; exit 1 ;;
esac
echo "AB-DONE ${1:-}"
