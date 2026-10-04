#!/bin/bash
# Apply the Wine patch set to a source tree.
#
#   tools/apply_patches.sh [--check] [tree]
#     --check   dry-run only (no changes), reports each patch as OK/SKIP/FAIL
#     tree      default: $CW/sources/wine/wine-11.18
#
# Order: patches/series/*.patch (shared base) then patches/local/**/*.patch (CSP-exclusive).
# Idempotent: a patch already applied is reported SKIP, not FAIL.
set -uo pipefail
CW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

CHECK=0
[ "${1:-}" = "--check" ] && { CHECK=1; shift; }
TREE=${1:-$CW/sources/wine/wine-11.18}
[ -d "$TREE" ] || { echo "no tree at $TREE"; exit 1; }

# A cumulative series cannot be validated by dry-running each patch against an unpatched tree
# (patch N legitimately fails until 1..N-1 are applied), and "already applied" cannot be detected by
# reverse-applying a single patch once later patches have changed the same context.  So --check
# extracts a pristine tarball into a scratch directory and applies the whole series there for real.
if [ "$CHECK" = 1 ]; then
  TARBALL=${CW_TARBALL:-/home/asdf/Downloads/wine-11.18.tar.xz}
  [ -f "$TARBALL" ] || { echo "check: no pristine tarball at $TARBALL"; exit 1; }
  SCRATCH=$CW/state/scratch/check-$$
  mkdir -p "$SCRATCH"
  trap 'rm -rf "$SCRATCH"' EXIT
  echo "check: extracting $TARBALL -> $SCRATCH"
  tar -xf "$TARBALL" -C "$SCRATCH" || exit 1
  TREE=$SCRATCH/wine-11.18
  [ -d "$TREE" ] || { echo "check: unexpected tarball layout"; exit 1; }
fi

cd "$TREE"

list_patches() {
  ls "$CW"/patches/series/*.patch 2>/dev/null | sort
  # local/: the dcomp patchset lives in a subdirectory; its numbered files apply in order.
  ls "$CW"/patches/local/*.patch 2>/dev/null | sort
  ls "$CW"/patches/local/dcomp-staging/[0-9]*.patch 2>/dev/null | sort
}

ok=0; skip=0; fail=0
for p in $(list_patches); do
  name=${p#"$CW"/}
  if patch -p1 --forward -i "$p" >/tmp/apply_$(basename "$p").log 2>&1; then
    echo "OK   $name"; ok=$((ok+1))
  elif patch -p1 --reverse --dry-run -i "$p" >/dev/null 2>&1; then
    echo "SKIP $name (already applied)"; skip=$((skip+1))
  else
    echo "FAIL $name  (see /tmp/apply_$(basename "$p").log)"; fail=$((fail+1))
  fi
done

echo "---- ok=$ok skip=$skip fail=$fail"
[ "$fail" -eq 0 ]
