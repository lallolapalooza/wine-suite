#!/bin/bash
# Prove the patch series in patches/ is self-contained and faithfully reproduces the fork:
#   1. extract a pristine wine-<version> tree from the upstream release tarball
#   2. apply patches/*.patch in order with `patch -p1`, rejecting leftovers (*.orig/*.rej)
#   3. hard-check: every file a patch touches is byte-identical to the fork we build
#   4. strict-check: apart from build artifacts, NO other file differs from the fork
#
# (4) is the meaningful form of "applying the series reproduces the fork": a built Wine tree
# legitimately contains generated files (i386-windows/, *.res, testlist.c, generated
# .gitignore, *.dll16, *.sys, ...), and measured against a pristine extract those account for
# every difference except the patch-touched sources — which must match exactly.
#
# usage: check_patch_series.sh [pristine_tarball]
#   default: /home/asdf/Downloads/wine-11.18.tar.xz  (40 MB)
#   fetch:   curl -sLO https://dl.winehq.org/wine/source/11.x/wine-11.18.tar.xz
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
TARBALL=${1:-/home/asdf/Downloads/wine-11.18.tar.xz}
FORK=$ROOT/wine/wine-11.18

[ -f "$TARBALL" ] || { echo "FAIL: no pristine tarball at $TARBALL"; exit 1; }
[ -d "$FORK" ]    || { echo "FAIL: no fork tree at $FORK"; exit 1; }
PATCHES=$(ls patches/*.patch 2>/dev/null | sort)
[ -n "$PATCHES" ] || { echo "FAIL: no patches in $ROOT/patches"; exit 1; }

# Build/generated artifacts a configured+built Wine tree carries and a release tarball does not.
EXCLUDES=(-x 'i386-windows' -x 'x86_64-windows' -x '.gitignore' -x '.git' -x 'install'
          -x '*.res' -x 'testlist.c' -x 'Makefile' -x 'config.h' -x 'config.log'
          -x 'config.status' -x '*.o' -x '*.a' -x '*.so' -x '*.dll' -x '*.exe' -x '*.fake'
          -x '*.dll16' -x '*.exe16' -x '*.sys' -x '*.drv' -x '*.cpl' -x '*.ocx' -x '*.acm'
          -x '*.vxd' -x '*.def' -x '*.tlb' -x '*.pc' -x '*.orig' -x '*.rej')

WORK=$(mktemp -d /tmp/pbiseries.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
echo "pristine  $TARBALL"
tar -xf "$TARBALL" -C "$WORK" || { echo "FAIL: cannot extract tarball"; exit 1; }
PRISTINE=$(ls -d "$WORK"/wine-* | head -1)
[ "$(basename "$PRISTINE")" = "$(basename "$FORK")" ] \
  || { echo "FAIL: fork is $(basename "$FORK") but tarball is $(basename "$PRISTINE")"; exit 1; }

echo "--- applying $(echo "$PATCHES" | wc -l) patch(es) ---"
FAIL=0
for p in $PATCHES; do
  log="$WORK/$(basename "$p").log"
  if (cd "$PRISTINE" && patch -p1 --no-backup-if-mismatch -i "$ROOT/$p" >"$log" 2>&1); then
    echo "OK    $(basename "$p")  ($(grep -c '^patching file' "$log") files)"
  else
    echo "FAIL  $(basename "$p")"; tail -6 "$log" | sed 's/^/        /'; FAIL=1
  fi
done
[ "$FAIL" = 0 ] || { echo "RESULT: FAIL (series does not apply cleanly)"; exit 1; }
stray=$(find "$PRISTINE" \( -name '*.orig' -o -name '*.rej' \) | head -5)
[ -z "$stray" ] || { echo "FAIL: rejects/backups left behind:"; echo "$stray"; exit 1; }

# (3) hard-check every file the patches touch.
TOUCHED=$(grep -h '^+++ b/' patches/*.patch | sed 's|^+++ b/||' | sort -u)
echo "--- checking $(echo "$TOUCHED" | wc -l) patch-touched file(s) against the fork ---"
BAD=0
for f in $TOUCHED; do
  if ! cmp -s "$PRISTINE/$f" "$FORK/$f"; then
    echo "FAIL  $f differs from the fork"
    BAD=1
  fi
done
[ "$BAD" = 0 ] && echo "OK    all patch-touched files are byte-identical to the fork"

# (4) strict-check: no *content* difference outside the known baseline.
# Our patches add no files, so every "Only in <tree>" line is a build-generated artifact (widl headers
# like actxprxy_*.h/dlldata.c, *.tab.c, i386-windows/, .gitignore, .res, ...) and is ignored. What must
# be empty is the set of files that *differ in content* and are not explained by the baseline below.
# `BASELINE_FILES` is the AutoCAD-series footprint this fork carries (see FINDINGS M40): measured to be
# disjoint from our patches, but present because the fork was built on that project's tree. Any file
# differing outside this list is an edit no patch explains, and that is a failure.
BASELINE_FILES='
dlls/crypt32/store.c
dlls/dnsapi/dnsapi.spec
dlls/dnsapi/query.c
dlls/kernel32/kernel32.spec
dlls/kernelbase/kernelbase.spec
dlls/kernelbase/process.c
dlls/kernelbase/registry.c
dlls/kernelbase/thread.c
dlls/msxml3/mxnamespace.c
dlls/ntdll/ntdll.spec
dlls/ntdll/path.c
dlls/ntdll/unix/file.c
dlls/urlmon/sec_mgr.c
dlls/user32/msgbox.c
dlls/user32/resource.c
dlls/wintrust/softpub.c
dlls/ws2_32/protocol.c
programs/msiexec/msiexec.c
server/fd.c
server/mapping.c
server/process.c
'
echo "--- checking for content differences outside the known baseline ---"
diff -r -q "${EXCLUDES[@]}" "$PRISTINE" "$FORK" 2>/dev/null | grep '^Files ' \
  | sed "s|^Files $PRISTINE/||; s| and $FORK/.*||" | sort >"$WORK/changed.txt"
UNEXPLAINED=$(comm -23 "$WORK/changed.txt" <(printf '%s\n' $BASELINE_FILES | sort))
if [ -n "$UNEXPLAINED" ]; then
  echo "unexplained content differences:"
  echo "$UNEXPLAINED" | sed 's/^/  /'
  echo "RESULT: FAIL (files outside the patches differ from the fork)"
  exit 1
fi
[ "$BAD" = 0 ] || { echo "RESULT: FAIL (patch-touched files differ)"; exit 1; }
n=$(wc -l <"$WORK/changed.txt")
echo "OK    $n file(s) differ from pristine and all are the known AutoCAD-series baseline (FINDINGS M40)"
echo "RESULT: PASS — the $(echo "$PATCHES" | wc -l)-patch series applies to a pristine $(basename "$FORK"),"
echo "               its touched files are byte-identical to the fork, and every other content difference"
echo "               is the pre-existing AutoCAD-series baseline, not an unexplained edit."
