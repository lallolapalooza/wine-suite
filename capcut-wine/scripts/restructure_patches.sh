#!/bin/bash
# Reorganise patches/ into the deliverable layout used by the sibling projects:
#   patches/series/   the shared base series that applies to pristine wine-11.18, in order
#   patches/local/    this project's OWN patches (CapCut-exclusive), numbered after the series
#   patches/sources/  untouched copies of the donor patch directories
#   patches/SERIES.tsv provenance of every series patch
# usage: restructure_patches.sh
set -eu
CCWS=/home/asdf/projects/capcut-wine
P=$CCWS/patches
cd "$P"

mkdir -p series local sources

# 1. move the numbered series patches (0001..) into series/
for f in [0-9][0-9][0-9][0-9]-*.patch; do
  [ -e "$f" ] || continue
  mv -n "$f" series/
done

# 2. donor copies
for d in acad-wine-main autocad2027-private-main powerbi revit-wine-main solidedge-wine-main; do
  src=""
  case "$d" in
    acad-wine-main|autocad2027-private-main|revit-wine-main) src=/home/asdf/projects/$d/patches ;;
    powerbi) src=/home/asdf/projects/powerbi/patches ;;
    solidedge-wine-main) src=/home/asdf/projects/solidedge-wine-main/patches/series ;;
  esac
  if [ -d "$src" ]; then
    mkdir -p "sources/$d"
    cp -n "$src"/*.patch "sources/$d/" 2>/dev/null || true
    echo "sources/$d: $(ls sources/$d | wc -l) patches"
  fi
done
mkdir -p sources/resolume-wine
cp -n /home/asdf/projects/resolume-wine/patches/local/*.patch sources/resolume-wine/ 2>/dev/null || true

# 3. provenance table: extend the merge agent's base-roles.tsv with the revit-derived additions
{
  echo -e "new\torigin\tsource_patch\tsubject"
  tail -n +4 base-roles.tsv 2>/dev/null | sed 's/^/ /' >/dev/null || true
  cat base-roles.tsv 2>/dev/null
  cat <<'EOF'
0023	revit-wine-main	0101-dcomp-implementation.patch	dcomp: implement the device/target/visual objects, commit and the composition surface path
0024	revit-wine-main	0102-dxgi-composition-swapchain-getdc.patch	dxgi: CreateSwapChainForComposition + per-present compositing + GDI back buffer surviving ResizeBuffers
0025	revit-wine-main	0100-ncrypt-import-ecc-key-blobs.patch	ncrypt: import ECC key blobs
EOF
} > SERIES.tsv

mv -n base-roles.tsv series/base-roles.tsv 2>/dev/null || true

echo "--- series (count $(ls series/*.patch | wc -l)) ---"
ls series/ | tail -8
echo "--- local ---"; ls -la local/ | tail -3
echo "--- sources ---"; ls sources/
