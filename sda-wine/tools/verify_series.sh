#!/bin/bash
# Prove that patches/series/ really is the union of the imported AutoCAD-on-Wine and
# Power BI-on-Wine patch sets, by content hash.
set -uo pipefail
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$SD"

sha() { sha1sum "$1" | cut -c1-12; }

echo "=== each series patch -> which imported set it came from ==="
for p in patches/series/*.patch; do
  h=$(sha "$p"); m=""
  for s in acad-wine-main autocad2027-private-main powerbi; do
    for q in patches/sources/$s/*.patch; do
      [ -f "$q" ] || continue
      [ "$(sha "$q")" = "$h" ] && m="$m $s"
    done
  done
  [ -z "$m" ] && m="  NOMATCH"
  printf "%-64s %s\n" "$(basename "$p")" "$m"
done

echo
echo "=== imported patches NOT represented in the series ==="
for q in patches/sources/acad-wine-main/*.patch patches/sources/powerbi/*.patch patches/sources/autocad2027-private-main/*.patch; do
  [ -f "$q" ] || continue
  h=$(sha "$q"); found=no
  for p in patches/series/*.patch; do [ "$(sha "$p")" = "$h" ] && found=yes; done
  [ "$found" = no ] && echo "  UNUSED $(basename "$(dirname "$q")")/$(basename "$q")"
done

echo
echo "counts: series=$(ls patches/series/*.patch | wc -l) acad-wine-main=$(ls patches/sources/acad-wine-main/*.patch | wc -l) powerbi=$(ls patches/sources/powerbi/*.patch | wc -l) autocad2027-private-main=$(ls patches/sources/autocad2027-private-main/*.patch | wc -l)"
