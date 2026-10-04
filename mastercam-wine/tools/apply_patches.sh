#!/bin/bash
# Apply the consolidated patch series (patches/series) and this project's own patches
# (patches/local) to a pristine Wine 11.18 tree, in filename order within each.
# usage: tools/apply_patches.sh <wine-tree> [--dry-run]
set -u
shopt -s nullglob
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TREE=${1:?usage: apply_patches.sh <wine-tree> [--dry-run]}
DRY=${2:-}
FLAGS=""
[ "$DRY" = "--dry-run" ] && FLAGS="--dry-run"
rc=0
for p in "$ROOT"/patches/series/*.patch "$ROOT"/patches/local/*.patch; do
  printf '%-70s ' "$(basename "$p")"
  if ( cd "$TREE" && patch -p1 -N --batch $FLAGS -i "$p" >/tmp/_applypatch.log 2>&1 ); then
    echo OK
  else
    echo FAIL; tail -8 /tmp/_applypatch.log; rc=1
  fi
done
exit $rc
