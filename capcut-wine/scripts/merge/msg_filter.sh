#!/bin/sh
# rewrite the two acad commits whose source patch files had no commit message
# (their subject was just the file name) to a real Wine-style subject.
read -r first_line
case "$first_line" in
  "0001-wintrust-WTD_CHOICE_BLOB-and-RFC3161-timestamp.patch")
      cat <<'EOF'
wintrust: implement WTD_CHOICE_BLOB buffers and RFC 3161 timestamp verification

Source patch 0001-wintrust-WTD_CHOICE_BLOB-and-RFC3161-timestamp.patch carried no
commit message, only the diff; this subject is derived from the patch content.
EOF
      ;;
  "0002-kernelbase-regf-hive-RegLoadAppKey.patch")
      cat <<'EOF'
kernelbase: load binary regf hive files in RegLoadAppKey

Source patch 0002-kernelbase-regf-hive-RegLoadAppKey.patch carried no commit
message, only the diff; this subject is derived from the patch content.
EOF
      ;;
  *)
      printf '%s\n' "$first_line"
      cat
      ;;
esac
