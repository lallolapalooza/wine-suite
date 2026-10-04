#!/bin/bash
# Generate a deliverable patch in the format the reference repo uses (cad-wine-main/patches): a prose header that
# states the symptom, the Windows behaviour restored and how it was verified, followed by a unified diff whose
# labels are `a/…`/`b/…` so the series applies with `patch -p1 -i <file>` against a pristine Wine tree.
#
#   tools/make_patch.sh <NNNN-slug> <header-file> [baseline-wine-tree] [files...]
#
# The optional `files` list (or PATCH_FILES) restricts the patch to those paths, which is what a slice needs when
# the tree also holds another slice's work - without it the whole tree is diffed and every slice's changes land in
# every patch.
#
# The baseline is the upstream+CAD-patched tree (`cad-wine-main/wine-11.18`), which was verified file-for-file
# identical to `wine/wine-11.18` before this project's changes — so the diff contains exactly our work and nothing
# else. Build output (`*-windows/`) and object files are excluded.
set -o pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SLUG=${1:?usage: make_patch.sh <NNNN-slug> <header-file> [baseline]}
HEADER=${2:?usage: make_patch.sh <NNNN-slug> <header-file> [baseline]}
BASE=${3:-/home/asdf/Downloads/cad-wine-main/wine-11.18}
shift 3 2>/dev/null || true
FILTER="$*"; FILTER=${FILTER:-${PATCH_FILES:-}}
included() { [ -z "$FILTER" ] && return 0; case " $FILTER " in *" $1 "*) return 0;; esac; return 1; }
FORK=$ROOT/wine/wine-11.18
OUT=$ROOT/patches
[ -d "$BASE" ] || { echo "baseline tree not found: $BASE" >&2; exit 2; }
[ -f "$HEADER" ] || { echo "header file not found: $HEADER" >&2; exit 2; }
mkdir -p "$OUT"
PATCH=$OUT/$SLUG.patch

# Which source files differ? Our fork tree has been configured and built while the baseline is clean source, so
# "diff -r" would sweep in generated files (Makefile, config.status, *.o/*.a, IDL-generated headers …). Restrict
# to source extensions and to files that exist in the baseline: that is exactly our work, nothing else.
mapfile -t FILES < <(cd "$FORK" && find . -type f \
    \( -name '*.c' -o -name '*.h' -o -name '*.idl' -o -name '*.spec' -o -name '*.in' -o -name '*.rc' \
       -o -name '*.def' -o -name '*.ac' -o -name '*.am' -o -name '*.py' -o -name '*.sh' \) \
    -not -path '*-windows/*' -not -path '*/tests/*.h' \
    | sed 's|^\./||' | sort | while read -r rel; do
        [ -f "$BASE/$rel" ] || continue
        included "$rel" || continue
        cmp -s "$BASE/$rel" "$FORK/$rel" || echo "$rel"
    done)

if [ "${#FILES[@]}" -eq 0 ]; then echo "no differences vs $BASE — nothing to write" >&2; exit 1; fi

{
    cat "$HEADER"
    for rel in "${FILES[@]}"; do
        [ -f "$FORK/$rel" ] || continue
        diff -u --label "a/$rel" --label "b/$rel" "$BASE/$rel" "$FORK/$rel"
    done
} > "$PATCH"

echo "wrote $PATCH"
echo "  files: ${FILES[*]}"
echo "  lines: $(wc -l < "$PATCH")"
# Sanity: the series has to apply to a pristine tree.
TMP=$(mktemp -d); cp -a "$BASE" "$TMP/wine" 2>/dev/null
if (cd "$TMP/wine" && patch -p1 --dry-run -s -i "$PATCH" >/dev/null 2>&1); then
    echo "  applies cleanly with 'patch -p1' against the baseline ✓"
else
    echo "  WARNING: does not apply cleanly against the baseline"
fi
rm -rf "$TMP"
