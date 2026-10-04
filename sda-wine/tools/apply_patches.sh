#!/bin/bash
# Apply the Wine patch set to a source tree.
#
#   tools/apply_patches.sh [--check] [tree]
#     --check   extract a pristine tarball into scratch and apply the whole series there for real
#     tree      default: $SD/sources/wine/wine-11.18
#
# Order: patches/series/*.patch (shared base: AutoCAD + Power BI) then patches/local/*.patch
# (Steinberg Download Assistant exclusive), then patches/local/<set>/[0-9]*.patch for staged sets.
set -uo pipefail
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

CHECK=0
[ "${1:-}" = "--check" ] && { CHECK=1; shift; }
TREE=${1:-$SD/sources/wine/wine-11.18}
[ -d "$TREE" ] || { echo "no tree at $TREE"; exit 1; }

if [ "$CHECK" = 1 ]; then
  TARBALL=${SD_TARBALL:-/home/asdf/Downloads/wine-11.18.tar.xz}
  [ -f "$TARBALL" ] || { echo "check: no pristine tarball at $TARBALL"; exit 1; }
  SCRATCH=$SD/state/scratch/check-$$
  mkdir -p "$SCRATCH"
  trap 'rm -rf "$SCRATCH"' EXIT
  echo "check: extracting $TARBALL -> $SCRATCH"
  tar -xf "$TARBALL" -C "$SCRATCH" || exit 1
  TREE=$SCRATCH/wine-11.18
  [ -d "$TREE" ] || { echo "check: unexpected tarball layout"; exit 1; }
fi

cd "$TREE"

list_patches() {
  ls "$SD"/patches/series/*.patch 2>/dev/null | sort
  ls "$SD"/patches/local/*.patch 2>/dev/null | sort
  for d in "$SD"/patches/local/*/; do
    [ -d "$d" ] || continue
    [ "$(basename "$d")" = candidates ] && continue
    ls "$d"[0-9]*.patch 2>/dev/null | sort
  done
}

ok=0; skip=0; fail=0
LOGDIR=$SD/logs/patchcheck
mkdir -p "$LOGDIR"
for p in $(list_patches); do
  name=${p#"$SD"/}
  log=$LOGDIR/$(basename "$p").log
  if patch -p1 --forward -i "$p" >"$log" 2>&1; then
    echo "OK   $name"; ok=$((ok+1))
  elif patch -p1 --reverse --dry-run -i "$p" >/dev/null 2>&1; then
    echo "SKIP $name (already applied)"; skip=$((skip+1))
  else
    echo "FAIL $name  (see $log)"; fail=$((fail+1))
  fi
done

echo "---- ok=$ok skip=$skip fail=$fail"
[ "$fail" -eq 0 ]
