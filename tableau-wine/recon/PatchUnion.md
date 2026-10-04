# PatchUnion - union series build notes

Task: merge the AutoCAD (15) and Power BI (7) series onto pristine Wine 11.18 and leave the patched tree.

## Result
- Union series: **20 patches** in `$P/patches/0001..0020`, `SERIES.md` written alongside.
- Tree: `$P/wine-11.18/` carries the whole series. Not built/configured (per task).
- Proof: `$P/recon/union-check/` = fresh tarball + series; all 20 patches rc=0, 0 rejects, 0 fuzz,
  0 offset; no `.orig`/`.rej`; `diff -rq` vs `$P/wine-11.18` clean (rc=0).
- Logs: `$P/logs/union/union-apply.log` (first run), `$P/logs/union/union-check.log` (proof).

## Inputs (22) -> union (20)
- 1 duplicate dropped: AutoCAD `0014-secur32-GetUserNameExW...` == Power BI `0005-...`
  (diff of the `--- a/` bodies: rc=0, no output -> byte-identical code). Kept Power BI 0005
  (its commit message is the strict superset, documenting the port). Final `0011`.
- 2 tests patches merged: AutoCAD `0017` + Power BI `0007` -> final `0020`.
  Only overlap is `dlls/secur32/tests/secur32.c`; Power BI's section is a strict superset
  (same hunks + the `LsaFreeReturnBuffer` check `@@ -716,7 +828,8 @@`), so AutoCAD's copy was dropped.
- Intra-series overlap AutoCAD `0006`+`0012` on `dlls/ws2_32/protocol.c`: disjoint hunks
  (line 45 vs 2162+), kept both, order preserved (final `0014` before `0015`).
- `.patch.new`: does not exist under `$P`; the stray file is only in
  `/home/asdf/projects/acad-wine-main/patches/`. Diagnostic AutoCAD 0005/0011 are not staged in `$P`
  either, so nothing to exclude.

## Order (low-level -> dlls -> tests)
server session-0, server completion-info, ntdll pipes, ntdll impersonate, kernelbase regf,
missing-exports, ntdll actctx | wintypes, secur32 spnego, secur32 LsaFreeReturnBuffer,
secur32 GetUserNameExW, wintrust, urlmon, ws2_32 hosts, ws2_32 NS_NLA, crypt32, winex11,
oledb32, msiexec | tests (merged).

## Fix applied
AutoCAD 0016 (final 0007) `dlls/ntdll/actctx.c` hunks applied at offset +2 (rc=0, fuzz=0), which
made GNU patch's default `--backup-if-mismatch` leave `actctx.c.orig`. Regenerated the two file
sections of `0007` exactly against pristine (commit message preserved). Verified byte-identical tree
content via `diff -rq` clean and 0 offset on re-apply.

## Measured
- `patch -p1 --dry-run -F0` per input alone on pristine: all 22 rc=0.
- Proof loop output: see the per-patch table in `$P/patches/SERIES.md`.
- `diff -rq` scratch vs tracked: no output, rc=0.
