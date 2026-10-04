#!/bin/bash
# Verify the guest-uploaded WebView2 runtime zip against recon/windows_webview2_filelist.txt
# usage: wv2_zip_verify.sh <zip> [workdir]
set -eu
ZIP=${1:?zip path}
WORK=${2:-/tmp/wv2verify}
ROOT=/home/asdf/Downloads/powerbi-linux
rm -rf "$WORK"
mkdir -p "$WORK"
unzip -q -o "$ZIP" -d "$WORK"
cd "$WORK"
# guest filelist format: "<relpath backslash-separated> | <size>"
find . -type f -printf '%P\t%s\n' | sed 's|/|\\|g' | sort > "$WORK/files.tsv"
sort "$ROOT/recon/windows_webview2_filelist.txt" | sed 's/ | /\t/' | sed 's/^\xef\xbb\xbf//' | sort > "$WORK/guest.tsv"
{
  echo "# extracted file list of $ZIP"
  echo "# format: <relpath with backslashes> | <size>"
  awk -F'\t' '{printf "%s | %s\n", $1, $2}' "$WORK/files.tsv" | sort
} > "$ROOT/recon/windows_webview2_zip_filelist.txt"
echo "=== entries (files) in zip: $(wc -l < "$WORK/files.tsv")"
echo "=== total bytes in zip:    $(awk -F'\t' '{s+=$2} END{print s+0}' "$WORK/files.tsv")"
echo "=== guest reference files: $(wc -l < "$WORK/guest.tsv")"
echo "=== guest reference bytes: $(awk -F'\t' '{s+=$2} END{print s+0}' "$WORK/guest.tsv")"
echo "=== files in guest reference but MISSING from zip ==="
comm -13 <(cut -f1 "$WORK/files.tsv" | sort) <(cut -f1 "$WORK/guest.tsv" | sort) | head -50
echo "=== files in zip but NOT in guest reference ==="
comm -23 <(cut -f1 "$WORK/files.tsv" | sort) <(cut -f1 "$WORK/guest.tsv" | sort) | head -50
echo "=== size mismatches (first 50) ==="
join -t$'\t' -j1 <(sort "$WORK/files.tsv") <(sort "$WORK/guest.tsv") | awk -F'\t' '$2!=$3 {print $1" zip="$2" guest="$3}' | head -50
echo "=== msedge.dll ==="
ls -l "$WORK/msedge.dll" 2>/dev/null || echo "msedge.dll NOT at archive root"
