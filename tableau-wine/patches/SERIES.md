# Union Wine 11.18 patch series (AutoCAD + Power BI)

Source: pristine `src/wine-11.18.tar.xz` (upstream Wine 11.18). Input series: 15 patches under
`patches/from-autocad/` and 7 under `patches/from-powerbi/` (22 total), all generated against this
same pristine tree (verified: each applies alone to pristine with `patch -p1 --dry-run -F0`, rc=0).
Union: **20 patches** (`patches/0001..0020`), ordered low-level (server/ntdll/kernelbase) -> dlls ->
programs -> tests.

Note on inputs: no `*.patch.new` artifact exists under `$P/patches/`; the stray
`0017-tests-cover-the-series.patch.new` lives only in the prior-art repo
`/home/asdf/projects/acad-wine-main/patches/` and was never staged here, so there is nothing to exclude.
The two diagnostic-only AutoCAD patches their README excludes - `0005 bcrypt: dump symmetric keys`
and `0011 user32: dump the licence-error caller` - are not among the staged inputs either
(`patches/from-autocad/` has no 0005 or 0011), so they are absent from the union.

## Series table

| # | subject | source (project + original #) | files | why it is in the series |
|---|---|---|---|---|
| 0001 | wineserver: run the service manager and the services it starts in session 0 | AutoCAD 0004 | `server/mapping.c`<br>`server/process.c` | Services have to see a real session 0 and a session-0 window station/desktop. |
| 0002 | server: allow associating non-overlapped handles with a completion port | AutoCAD 0008 | `server/fd.c` | Licensing/browser stacks bind non-overlapped handles to IOCPs. |
| 0003 | ntdll: make handles on fd-backed Unix pipes behave like Windows pipes | AutoCAD 0009 | `dlls/ntdll/unix/file.c` | Pipe peeking/overlapped semantics used by the licensing and IPC layers. |
| 0004 | ntdll: implement NtImpersonateAnonymousToken, so the Analysis Services engine of Power BI Desktop can start | Power BI 0002 | `dlls/ntdll/unix/security.c` | AS engine (msmdsrv.exe) calls it at startup; without it the engine exits and Power BI cannot connect. Generic. |
| 0005 | kernelbase/regf-hive: implement RegLoadAppKey on the binary regf format | AutoCAD 0002 | `dlls/kernelbase/registry.c` | Installer/licensing reads binary (regf) hive files via RegLoadAppKey. |
| 0006 | kernel32/kernelbase/ntdll/dnsapi: export the APIs the licensing and browser stacks probe for | AutoCAD 0010 | `dlls/kernelbase/thread.c`<br>`dlls/kernelbase/process.c`<br>`dlls/kernelbase/kernelbase.spec`<br>`dlls/kernel32/kernel32.spec`<br>`dlls/ntdll/path.c`<br>`dlls/ntdll/ntdll.spec`<br>`dlls/dnsapi/query.c`<br>`dlls/dnsapi/dnsapi.spec` | FlsAlloc/CET/long-path/\??\ exports probed by the installer and licensing DLLs. |
| 0007 | ntdll/actctx: honour <probing privatePath="..."> from the application configuration file | AutoCAD 0016 | `dlls/kernel32/tests/actctx.c`<br>`dlls/ntdll/actctx.c` | Native SxS privatePath probing; installers fail with STATUS_DLL_NOT_FOUND without it. |
| 0008 | wintypes: resolve Windows Runtime type metadata, so .NET can bind WinRT types | Power BI 0001 | `dlls/wintypes/main.c`<br>`dlls/wintypes/Makefile.in`<br>`dlls/wintypes/wintypes.spec`<br>`include/rometadataresolution.h` | WinRT metadata resolution for the .NET/WinRT interop used by the app. |
| 0009 | secur32: implement RFC 4178 SPNEGO in the Negotiate package, both roles | Power BI 0003 | `programs/lsass/negotiate.c` | Negotiate/SPNEGO auth for identity; both client and server roles. |
| 0010 | secur32: return an NTSTATUS from LsaFreeReturnBuffer, not VirtualFree's BOOL | Power BI 0004 | `dlls/secur32/lsa.c` | Correct NTSTATUS return contract for the SSPI buffer-free path. |
| 0011 | secur32: answer GetUserNameExW's NameUserPrincipal and NameDnsDomain from the machine's domain | AutoCAD 0014 + Power BI 0005 (identical code) | `dlls/secur32/secur32.c` | Identity/UPN lookups; AutoCAD's oneauth and Power BI's AcquirePlatformEmail both call format 8. Duplicate merged - see conflict log. |
| 0012 | wintrust: WTD_CHOICE_BLOB and RFC3161 timestamp verification | AutoCAD 0001 | `dlls/wintrust/softpub.c` | AppX/P7x SIP and RFC3161 countersignature verification. |
| 0013 | urlmon: keep the "res" scheme out of the empty-host URLZONE_INVALID rule | AutoCAD 0003 | `dlls/urlmon/sec_mgr.c` | res:// URL zone mapping used by the app's embedded browser. |
| 0014 | ws2_32: resolve names through the Windows hosts file | AutoCAD 0006 | `dlls/ws2_32/protocol.c` | Name resolution through the Windows hosts file. |
| 0015 | ws2_32: answer Network Location Awareness (NS_NLA) lookups | AutoCAD 0012 | `dlls/ws2_32/protocol.c` | NLA namespace lookups used by the connectivity stack. |
| 0016 | crypt32: provide the group-policy and enterprise system certificate stores | AutoCAD 0007 | `dlls/crypt32/store.c` | Group-policy/enterprise cert stores the licensing stack opens. |
| 0017 | winex11: ignore BadWindow/BadDrawable X errors on every display connection | AutoCAD 0013 | `dlls/winex11.drv/x11drv_main.c` | Robustness: stale-window X errors abort the display driver. |
| 0018 | oledb32: convert VARIANT to DBTYPE_I8 and DBTYPE_BOOL, so a natively bound 64-bit or boolean column can be read | Power BI 0006 | `dlls/oledb32/convert.c` | Native binding of 64-bit/boolean columns in the data provider. |
| 0019 | msiexec: parse the command line with the Windows rules, so a property value ending in a backslash survives | AutoCAD 0015 | `programs/msiexec/msiexec.c` | MSI installers pass property values ending in a backslash. |
| 0020 | tests: cover the merged series with Wine's own test suite | AutoCAD 0017 + Power BI 0007 (merged) | `dlls/ntdll/tests/Makefile.in`<br>`dlls/ntdll/tests/impersonate.c`<br>`dlls/secur32/tests/secur32.c`<br>`dlls/secur32/tests/negotiate.c`<br>`dlls/oledb32/tests/convert.c`<br>`dlls/wintypes/tests/wintypes.c`<br>`dlls/advapi32/tests/registry.c`<br>`dlls/crypt32/tests/store.c`<br>`dlls/dnsapi/tests/query.c`<br>`dlls/kernel32/tests/file.c`<br>`dlls/kernel32/tests/process.c`<br>`dlls/kernel32/tests/thread.c`<br>`dlls/ntdll/tests/path.c`<br>`dlls/ntdll/tests/pipe.c`<br>`dlls/urlmon/tests/sec_mgr.c`<br>`dlls/wintrust/tests/softpub.c`<br>`dlls/ws2_32/tests/protocol.c` | One regression test per behaviour patch, in each module's tests suite. |
| 0021 | userenv: implement DeriveAppContainerSidFromAppContainerName | new (post-union, generic) | `dlls/userenv/userenv.spec`<br>`dlls/userenv/Makefile.in`<br>`dlls/userenv/userenv_main.c`<br>`dlls/userenv/tests/userenv.c` | Qt WebEngine/Chromium 122 statically imports it and Wine bound it to an abort thunk; derives the Windows AppContainer package SID (lowercase name, SHA-256, first 28 bytes as seven little-endian subauthorities). |
| 0022 | user32: implement SkipPointerFrameMessages | new (post-union, generic) | `dlls/user32/user32.spec`<br>`dlls/user32/input.c`<br>`dlls/user32/tests/input.c` | Qt's touch handler calls it on every pointer frame; Wine had it as a commented-out stub, so the import aborted the process. No-op returning TRUE (Wine keeps no per-frame pointer queue). |

`0021` and `0022` are **post-union and generic**, not app-exclusive (measured 2026-10-04): they are the two
genuinely missing exports the payload import audit found (`recon/OPENSOURCE_TRACE.md` §2). Any Qt 6 / Chromium 122
application can hit them, and the Tableau activation screen was reached *without* them. They are not part of the
AutoCAD/Power BI union and were generated directly against the same pristine `src/wine-11.18.tar.xz`.
Both carry their regression test in the same patch.

## Duplicate / conflict log

**1. `dlls/secur32/secur32.c` - AutoCAD 0014 vs Power BI 0005 (duplicate, dropped one).**
Both patches carry the same subject. Proof of duplication: extracting each patch's diff body
(`sed -n '/^--- a\//,$p'`) and diffing them returns **rc=0 with no output** - the code hunks (the
`get_dns_domain()` helper, the `NameUserPrincipal`/`NameDnsDomain` cases, and the removal of those
two labels from the FIXME arm) are byte-identical. The commit messages differ: Power BI 0005's
message is a strict superset, explicitly recording that the hunk is ported from the AutoCAD series'
0014. Resolution: kept **Power BI 0005** as final `0011`; **AutoCAD 0014 dropped** as a duplicate.
The resulting tree is identical either way.

**2. `dlls/secur32/tests/secur32.c` - AutoCAD 0017 vs Power BI 0007 (merged, superset kept).**
Both add the same `testGetUserNameEx_domain()` test. The include hunk (`@@ -19,9 +19,11 @@`), the
function hunk (`@@ -251,6 +253,116 @@`) and the `START_TEST` wiring are identical. Power BI 0007
is a **strict superset** for this file: it also adds a `LsaFreeReturnBuffer` return-value check
(`@@ -716,7 +828,8 @@`, covering its 0004) which shifts its `START_TEST` hunk to `@@ -760,7 +873,10 @@`
(vs AutoCAD's `+872`). Resolution: the merged tests patch `0020` carries Power BI 0007's
`dlls/secur32/tests/secur32.c` section verbatim; the AutoCAD 0017 copy of that one file section was
dropped. Every other test module in the two series is disjoint and is carried verbatim
(17 file sections total in `0020`).

**3. `dlls/ws2_32/protocol.c` - AutoCAD 0006 + AutoCAD 0012 (intra-series, no hand-merge needed).**
Both from the same series. Their hunks are in disjoint regions (`@@ -45,14 +45,87 @@` vs
`@@ -2162,14 +2162,122 @@` and later), so plain sequential application in the original order
(0006 before 0012, final `0014` before `0015`) is clean. Kept both; no conflict.

**4. Line offsets in AutoCAD 0016 (final `0007`).** As first applied, AutoCAD 0016's
`dlls/ntdll/actctx.c` hunks landed at `offset 2 lines` (rc=0, fuzz=0), which GNU patch's default
`--backup-if-mismatch` turned into a stray `actctx.c.orig`. The two file sections of `0007` were
regenerated exactly against pristine (`diff -u --label a/... --label b/...`), preserving the commit
message, so the series now applies with **0 offset**, leaves no backup files, and the regenerated
patch produces a tree byte-identical to the originally-applied one (`diff -rq` clean).

No other cross- or intra-series file overlap exists: a `+++ b/` file-set intersection over all 22
inputs yields only the three pairs above.

## Apply command (exact)

```sh
cd /home/asdf/projects/tableau-wine
tar -xf src/wine-11.18.tar.xz -C .
cd wine-11.18
for f in ../patches/[0-9][0-9][0-9][0-9]-*.patch; do patch -p1 -i "$f"; done
```

## From-scratch proof

Fresh extraction into `$P/recon/union-check/`, then the exact loop above; full log at
`logs/union/union-check.log`. Every patch: rc=0, rejects=0, fuzz=0, offset=0.

```text
=== 0009-secur32-negotiate-spnego.patch rc=0
patching file programs/lsass/negotiate.c
=== 0010-secur32-LsaFreeReturnBuffer.patch rc=0
patching file dlls/secur32/lsa.c
=== 0011-secur32-GetUserNameExW-NameUserPrincipal-NameDnsDomain.patch rc=0
patching file dlls/secur32/secur32.c
=== 0012-wintrust-WTD_CHOICE_BLOB-and-RFC3161-timestamp.patch rc=0
patching file dlls/wintrust/softpub.c
=== 0013-urlmon-MapUrlToZone-res-scheme-empty-host.patch rc=0
patching file dlls/urlmon/sec_mgr.c
=== 0014-ws2_32-windows-hosts-file.patch rc=0
patching file dlls/ws2_32/protocol.c
=== 0015-ws2_32-NS_NLA-lookups.patch rc=0
patching file dlls/ws2_32/protocol.c
=== 0016-crypt32-group-policy-enterprise-stores.patch rc=0
patching file dlls/crypt32/store.c
=== 0017-winex11-ignore-stale-window-errors.patch rc=0
patching file dlls/winex11.drv/x11drv_main.c
=== 0018-oledb32-DataConvert-VARIANT-I8-and-BOOL.patch rc=0
patching file dlls/oledb32/convert.c
=== 0019-msiexec-Windows-command-line-parsing.patch rc=0
patching file programs/msiexec/msiexec.c
=== 0020-tests-cover-the-series.patch rc=0
patching file dlls/ntdll/tests/Makefile.in
patching file dlls/ntdll/tests/impersonate.c
patching file dlls/secur32/tests/secur32.c
patching file dlls/secur32/tests/negotiate.c
patching file dlls/oledb32/tests/convert.c
patching file dlls/wintypes/tests/wintypes.c
patching file dlls/advapi32/tests/registry.c
patching file dlls/crypt32/tests/store.c
patching file dlls/dnsapi/tests/query.c
patching file dlls/kernel32/tests/file.c
patching file dlls/kernel32/tests/process.c
patching file dlls/kernel32/tests/thread.c
patching file dlls/ntdll/tests/path.c
patching file dlls/ntdll/tests/pipe.c
patching file dlls/urlmon/tests/sec_mgr.c
patching file dlls/wintrust/tests/softpub.c
patching file dlls/ws2_32/tests/protocol.c
```

### Per-patch result (parsed from `logs/union/union-check.log`)

```text
status | # | rc | rejects/failed | fuzz | offset | files patched
---|---|---|---|---|---|---
OK | 0001 | 0 | 0 | 0 | 0 | 2 |
OK | 0002 | 0 | 0 | 0 | 0 | 1 |
OK | 0003 | 0 | 0 | 0 | 0 | 1 |
OK | 0004 | 0 | 0 | 0 | 0 | 1 |
OK | 0005 | 0 | 0 | 0 | 0 | 1 |
OK | 0006 | 0 | 0 | 0 | 0 | 8 |
OK | 0007 | 0 | 0 | 0 | 0 | 2 |
OK | 0008 | 0 | 0 | 0 | 0 | 4 |
OK | 0009 | 0 | 0 | 0 | 0 | 1 |
OK | 0010 | 0 | 0 | 0 | 0 | 1 |
OK | 0011 | 0 | 0 | 0 | 0 | 1 |
OK | 0012 | 0 | 0 | 0 | 0 | 1 |
OK | 0013 | 0 | 0 | 0 | 0 | 1 |
OK | 0014 | 0 | 0 | 0 | 0 | 1 |
OK | 0015 | 0 | 0 | 0 | 0 | 1 |
OK | 0016 | 0 | 0 | 0 | 0 | 1 |
OK | 0017 | 0 | 0 | 0 | 0 | 1 |
OK | 0018 | 0 | 0 | 0 | 0 | 1 |
OK | 0019 | 0 | 0 | 0 | 0 | 1 |
OK | 0020 | 0 | 0 | 0 | 0 | 17 |
```

20/20 patches: rc=0, 0 rejects, 0 fuzz, 0 offset.

Proof of tree equality, and a note on the shared build tree:

* At the moment the proof run finished, `diff -rq recon/union-check/wine-11.18 wine-11.18` printed
  **nothing** (rc=0) - the tracked tree was exactly the series applied to pristine.
* A parallel build process then wrote generated build outputs into `wine-11.18/` (`config.status`
  mtime 22:37, with `make -j6` observed running); it was not started by this task, and `BuildEnv`
  reports its own recon was read-only with no such files present at the time. So the tree
  now also holds the generated build outputs. Excluding those, equality is unchanged and total:
  `diff -rq recon/union-check/wine-11.18 wine-11.18 | grep -v '^Only in'` prints nothing, and
  `diff -rq ... | grep -c 'differ$'` is **0**. Every extra entry is `configure`/`make` output
  (Makefiles, `.gitignore`, `*.o`, `include/config.h`, `po/*.mo`, `tools/*`), not series content.

```sh
diff -rq recon/union-check/wine-11.18 wine-11.18 | grep -v '^Only in'   # prints nothing
diff -rq recon/union-check/wine-11.18 wine-11.18 | grep -c 'differ$'    # prints 0
```

## Patch checksums

| # | md5 | file sections |
|---|---|---|
| 0001 | `fb322a38a3b7410b9548115a13275fc3` | 2 |
| 0002 | `1b84b17bf6dfe366ea7004c211eadaee` | 1 |
| 0003 | `8ffc49f3701bbf712ccc424f4fbcc078` | 1 |
| 0004 | `9cf91c369bc77663208ed854e190b4d0` | 1 |
| 0005 | `2121526693a3c54c608f1bd84dd53003` | 1 |
| 0006 | `d9978a92e3d7491dc6cefddbb563aa13` | 8 |
| 0007 | `7fbbbb683a1486b6f7bdc32eb008726f` | 2 |
| 0008 | `e0fb62871271aec3d781c741b639a1d9` | 4 |
| 0009 | `fd2186daf6e30c6f4cbf39579364ad63` | 1 |
| 0010 | `9f94b54f60b0d08a9289a3b478424ba7` | 1 |
| 0011 | `7a284779af7405bec585f6e354ae06a0` | 1 |
| 0012 | `7058c50f2f0a8c6a1a6652b7ecdb5e4b` | 1 |
| 0013 | `5365088448f0cba507f298e739e3bf18` | 1 |
| 0014 | `08c827815b0024ac71e7d2dad98ada53` | 1 |
| 0015 | `35fe2dd8fd7e0711097aefbb19e1d2d6` | 1 |
| 0016 | `ac915fb3acddb56ff940fb03f44690e5` | 1 |
| 0017 | `caff49c45bfbe5c45698d6f83a2012dc` | 1 |
| 0018 | `f0383e532ec750edf107fc2a220d0bf9` | 1 |
| 0019 | `226f87417374d59cdeb5c66c3e39e85d` | 1 |
| 0020 | `71b1224e651ed3330770882dcaee7ce1` | 17 |
| 0021 | `059745c548f8b2f89d5aab6c354774bf` | 4 |
| 0022 | `e48b46bbf2b10a4ffb33050a90522645` | 3 |
