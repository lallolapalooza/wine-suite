# Patch catalogue — Tableau Desktop 2026.2.3 on Wine

Every Wine patch used by this project. The tree that is built here (`wine-11.18/`) is pristine
upstream `src/wine-11.18.tar.xz` (Wine 11.18) plus the 22 patches under `patches/` numbered
`0001`–`0022`, applied in that order:

* `0001`–`0020` — the **union** of the AutoCAD series (`patches/from-autocad/`, 15 patches) and the
  Power BI series (`patches/from-powerbi/`, 7 patches);
* `0021`–`0022` — **post-union** patches generated for this project from the Qt/Chromium source
  trace, covering the two genuine missing exports found by the payload load-time import audit
  (`recon/OPENSOURCE_TRACE.md` §2). They are generic Wine gaps, not app-exclusive (see the
  classification section), and they are not required to reach the activation screen.

`patches/SERIES.md` is the authoritative series record; this file is the catalogue, with the apply
order, the verification, the classification verdict and the app-exclusive section.

Provenance: for every union row, the "why it is in the series" column repeats the reason carried by
the source series (each source patch documents its own symptom); it is not a re-measured Tableau
failure, and several entries are generic Wine gaps rather than observed Tableau crashes. Source for
the union rows: `patches/SERIES.md` §"Series table". Verification status: the built `wine-install/`
binary is the **20-patch-union build**; `0021`/`0022` are in the source tree but were not yet
recompiled in (`STATE.md` 04:45Z).

## Union series (`patches/0001..0020`)

| # | subject | provenance (project + original #) | why it is in the series | files touched |
|---|---|---|---|---|
| 0001 | wineserver: run the service manager and the services it starts in session 0 | AutoCAD 0004 | Services must see a real session 0 and a session-0 window station/desktop | `server/mapping.c`, `server/process.c` |
| 0002 | server: allow associating non-overlapped handles with a completion port | AutoCAD 0008 | Licensing/browser stacks bind non-overlapped handles to IOCPs | `server/fd.c` |
| 0003 | ntdll: make handles on fd-backed Unix pipes behave like Windows pipes | AutoCAD 0009 | Pipe peeking / overlapped semantics used by the licensing and IPC layers | `dlls/ntdll/unix/file.c` |
| 0004 | ntdll: implement NtImpersonateAnonymousToken (Power BI's AS engine calls it) | Power BI 0002 | AS engine (`msmdsrv.exe`) calls it at startup; without it the engine exits. Generic | `dlls/ntdll/unix/security.c` |
| 0005 | kernelbase/regf-hive: implement RegLoadAppKey on the binary regf format | AutoCAD 0002 | Installer/licensing reads binary (regf) hive files via RegLoadAppKey | `dlls/kernelbase/registry.c` |
| 0006 | kernel32/kernelbase/ntdll/dnsapi: export the APIs the licensing and browser stacks probe for | AutoCAD 0010 | FlsAlloc / CET / long-path / `\??\` exports probed by installer and licensing DLLs | `dlls/kernelbase/{thread,process}.c`, `dlls/kernelbase/kernelbase.spec`, `dlls/kernel32/kernel32.spec`, `dlls/ntdll/path.c`, `dlls/ntdll/ntdll.spec`, `dlls/dnsapi/{query.c,dnsapi.spec}` |
| 0007 | ntdll/actctx: honour `<probing privatePath="...">` from the application configuration file | AutoCAD 0016 | Native SxS privatePath probing; installers fail with STATUS_DLL_NOT_FOUND without it | `dlls/ntdll/actctx.c`, `dlls/kernel32/tests/actctx.c` |
| 0008 | wintypes: resolve Windows Runtime type metadata, so .NET can bind WinRT types | Power BI 0001 | WinRT metadata resolution for the .NET/WinRT interop used by the app | `dlls/wintypes/{main.c,Makefile.in,wintypes.spec}`, `include/rometadataresolution.h` |
| 0009 | secur32: implement RFC 4178 SPNEGO in the Negotiate package, both roles | Power BI 0003 | Negotiate/SPNEGO auth for identity, both client and server roles | `programs/lsass/negotiate.c` |
| 0010 | secur32: return an NTSTATUS from LsaFreeReturnBuffer, not VirtualFree's BOOL | Power BI 0004 | Correct NTSTATUS return contract for the SSPI buffer-free path | `dlls/secur32/lsa.c` |
| 0011 | secur32: answer GetUserNameExW's NameUserPrincipal and NameDnsDomain from the machine's domain | AutoCAD 0014 + Power BI 0005 (identical code; Power BI copy kept) | Identity/UPN lookups; AutoCAD's oneauth and Power BI's AcquirePlatformEmail both call format 8. Duplicate merged — see the conflict log | `dlls/secur32/secur32.c` |
| 0012 | wintrust: WTD_CHOICE_BLOB and RFC3161 timestamp verification | AutoCAD 0001 | AppX/P7x SIP and RFC3161 countersignature verification | `dlls/wintrust/softpub.c` |
| 0013 | urlmon: keep the "res" scheme out of the empty-host URLZONE_INVALID rule | AutoCAD 0003 | `res://` URL zone mapping used by the app's embedded browser | `dlls/urlmon/sec_mgr.c` |
| 0014 | ws2_32: resolve names through the Windows hosts file | AutoCAD 0006 | Name resolution through the Windows hosts file | `dlls/ws2_32/protocol.c` |
| 0015 | ws2_32: answer Network Location Awareness (NS_NLA) lookups | AutoCAD 0012 | NLA namespace lookups used by the connectivity stack | `dlls/ws2_32/protocol.c` |
| 0016 | crypt32: provide the group-policy and enterprise system certificate stores | AutoCAD 0007 | Group-policy/enterprise cert stores the licensing stack opens | `dlls/crypt32/store.c` |
| 0017 | winex11: ignore BadWindow/BadDrawable X errors on every display connection | AutoCAD 0013 | Robustness: stale-window X errors abort the display driver | `dlls/winex11.drv/x11drv_main.c` |
| 0018 | oledb32: convert VARIANT to DBTYPE_I8 and DBTYPE_BOOL, so a natively bound 64-bit or boolean column can be read | Power BI 0006 | Native binding of 64-bit/boolean columns in the data provider | `dlls/oledb32/convert.c` |
| 0019 | msiexec: parse the command line with the Windows rules, so a property value ending in a backslash survives | AutoCAD 0015 | MSI installers pass property values ending in a backslash | `programs/msiexec/msiexec.c` |
| 0020 | tests: cover the merged series with Wine's own test suite | AutoCAD 0017 + Power BI 0007 (merged) | One regression test per behaviour patch, in each module's suite | 17 test files (ntdll, secur32, oledb32, wintypes, advapi32, crypt32, dnsapi, kernel32, urlmon, wintrust, ws2_32) |

## Post-union patches (`patches/0021..0022`)

Both were generated for this project after the payload load-time import audit
(`recon/OPENSOURCE_TRACE.md` §2) found the only two genuine missing exports. Each carries its own
regression test in the same patch. They are **generic** Wine gaps (any Qt 6.5 / Chromium 122 app
hits them), not Tableau-specific code.

| # | subject | provenance | why it is in the series | files touched |
|---|---|---|---|---|
| 0021 | userenv: implement DeriveAppContainerSidFromAppContainerName | post-union, from the Tableau payload import audit (`recon/OPENSOURCE_TRACE.md` §2) | `Qt6WebEngineCore.dll` and `QtWebEngineProcess.exe` statically import it and Wine bound it to an abort thunk; Wine's AppContainer support had only `CreateAppContainerProfile` as a stub. Derives the Windows AppContainer package SID (lowercase name, SHA-256 over UTF-16, first 28 bytes as seven little-endian subauthorities) | `dlls/userenv/userenv.spec`, `dlls/userenv/Makefile.in`, `dlls/userenv/userenv_main.c`, `dlls/userenv/tests/userenv.c` |
| 0022 | user32: implement SkipPointerFrameMessages | post-union, from the Tableau payload import audit (`recon/OPENSOURCE_TRACE.md` §2) | `plugins/platforms/qwindows.dll` imports it and Wine had it as a commented-out stub, so the import aborted the process; it is called only on Qt's touch-pointer path. No-op returning TRUE (Wine keeps no per-frame pointer queue) | `dlls/user32/user32.spec`, `dlls/user32/input.c`, `dlls/user32/tests/input.c` |

Neither patch is required for the "Activate Tableau" screen (`STATE.md` 04:52Z; the screen was
reached with the 20-patch union build in `wine-install/`).

## Patch classification: app-exclusive verdict

**No app-exclusive Wine patch was needed for Tableau Desktop 2026.2.3.** The activation window was
reached with the 20-patch AutoCAD+Power BI union applied to pristine Wine 11.18 and *no*
Tableau-specific Wine change. What Tableau additionally needed beyond Wine upstream was
**configuration, not code**: the bundle's own VC++ 2022 redistributable (for `mfc140u.dll`) and the
MSI's own install state (registry, `FNPLicensingService64`, Trusted Storage), all installed by the
*unmodified* bundle under Wine (`STATE.md` 04:48Z/04:52Z, `recon/INSTALLER_WINE.md`).

* `patches/app-exclusive/` is **empty** (verified: `ls -A patches/app-exclusive/` → no output).
* `0021`/`0022` are generic gaps surfaced by reading Qt/Chromium sources, not app-exclusive changes.
* **Per-patch necessity for Tableau was not bisected.** Running the app with the whole union proves
  sufficiency of the union, not the necessity of each patch; establishing that would need N rebuilds
  (`STATE.md` 04:52Z).

Wording discrepancy to reconcile (`patches/SERIES.md`, not owned by this document's author):
`SERIES.md`'s series table labels `0021`/`0022` "Tableau (app-exclusive, new)" and its prose calls
them "the Tableau app-exclusive additions", while `STATE.md` 04:52Z and the empty
`patches/app-exclusive/` directory say the opposite. This catalogue follows `STATE.md` (the state of
record) and the directory marker; `SERIES.md` should be corrected to call them post-union/generic.

## Order and conflicts

Order is low-level (server / ntdll / kernelbase) → dlls → programs → tests; `0001`–`0020` follow the
union numbering, and `0021`/`0022` are appended on top. Conflict log for the union
(`patches/SERIES.md` §"Duplicate / conflict log"):

1. `dlls/secur32/secur32.c` — AutoCAD 0014 and Power BI 0005 are byte-identical in their code
   hunks; the Power BI copy (whose commit message documents the port) is final 0011, the AutoCAD
   copy was dropped.
2. `dlls/secur32/tests/secur32.c` — Power BI 0007 is a strict superset for this file (same hunks
   plus an `LsaFreeReturnBuffer` return-value check); the merged tests patch 0020 carries Power BI's
   section and drops the AutoCAD 0017 copy of that one file section.
3. `dlls/ws2_32/protocol.c` — AutoCAD 0006 and 0012 (final 0014/0015) are intra-series and touch
   disjoint regions; plain sequential application is clean.
4. AutoCAD 0016 (final 0007) `dlls/ntdll/actctx.c` hunks applied at `offset 2` and left an
   `.orig` backup; the two file sections were regenerated exactly against pristine so the series
   applies at 0 offset and leaves no backups.

No other cross- or intra-series file overlap exists among the 22 union inputs (a `+++ b/` file-set
intersection yields only the three pairs above). `0021`/`0022` touch modules no union patch touches.

## Apply (exact command)

```sh
cd /home/asdf/projects/tableau-wine
tar -xf src/wine-11.18.tar.xz -C .
cd wine-11.18
for f in ../patches/[0-9][0-9][0-9][0-9]-*.patch; do patch -p1 -i "$f"; done
```

The glob picks up all 22 patches in order.

## Verification

* **Union `0001`–`0020`** — from-scratch proof (`patches/SERIES.md` §"From-scratch proof"): fresh
  extraction into `recon/union-check/`, then the loop above. Result: **20/20 patches rc=0, 0 rejects,
  0 fuzz, 0 offset**; every patched file byte-identical to the built tree; full log
  `logs/union/union-check.log`. The scratch tree `recon/union-check/` was later deleted to reclaim
  disk, so re-verify with the loop above or with `tools/check_patch_series.sh`. Note that
  `tools/check_patch_series.sh` as copied expects the fork at `wine/wine-11.18`; this project keeps
  the tree at `wine-11.18/`, so point it at the right tree (or use the loop) when re-running.
* **Post-union `0021`/`0022`** (`STATE.md` 04:45Z): both compile for i386 **and** x86_64
  (`make dlls/userenv/all dlls/user32/all -j4`, rc=0, no warnings); the exports are visible in the
  built DLLs via `objdump -p`; each carries a Wine-suite test in its module (compile-checked only,
  because this tree is configured `--disable-tests`); both apply cleanly forward to a pristine
  extraction and reverse to the built tree. A single combined from-scratch proof over all 22 patches
  had **not** been re-run as of this writing.

## Checksums

`md5sum patches/[0-9][0-9][0-9][0-9]-*.patch`; `0001`–`0020` verified identical to
`patches/SERIES.md`, `0021`/`0022` taken from `patches/SERIES.md`:

| # | md5 | # | md5 |
|---|---|---|---|
| 0001 | `fb322a38a3b7410b9548115a13275fc3` | 0012 | `7058c50f2f0a8c6a1a6652b7ecdb5e4b` |
| 0002 | `1b84b17bf6dfe366ea7004c211eadaee` | 0013 | `5365088448f0cba507f298e739e3bf18` |
| 0003 | `8ffc49f3701bbf712ccc424f4fbcc078` | 0014 | `08c827815b0024ac71e7d2dad98ada53` |
| 0004 | `9cf91c369bc77663208ed854e190b4d0` | 0015 | `35fe2dd8fd7e0711097aefbb19e1d2d6` |
| 0005 | `2121526693a3c54c608f1bd84dd53003` | 0016 | `ac915fb3acddb56ff940fb03f44690e5` |
| 0006 | `d9978a92e3d7491dc6cefddbb563aa13` | 0017 | `caff49c45bfbe5c45698d6f83a2012dc` |
| 0007 | `7fbbbb683a1486b6f7bdc32eb008726f` | 0018 | `f0383e532ec750edf107fc2a220d0bf9` |
| 0008 | `e0fb62871271aec3d781c741b639a1d9` | 0019 | `226f87417374d59cdeb5c66c3e39e85d` |
| 0009 | `fd2186daf6e30c6f4cbf39579364ad63` | 0020 | `71b1224e651ed3330770882dcaee7ce1` |
| 0010 | `9f94b54f60b0d08a9289a3b478424ba7` | 0021 | `059745c548f8b2f89d5aab6c354774bf` |
| 0011 | `7a284779af7405bec585f6e354ae06a0` | 0022 | `e48b46bbf2b10a4ffb33050a90522645` |

## App-exclusive patches

**`patches/app-exclusive/` is empty as of this writing.** Check with:

```sh
ls -A patches/app-exclusive/    # no output
```

This directory is reserved for Wine changes made specifically because of Tableau Desktop 2026.2.3 —
changes that are not a general Wine gap. **None were needed**: the acceptance screen was reached
with the generic union plus the app's own installer state (see the classification verdict above), so
the honest answer to "which patches are exclusive to this app" is: none. Any future Tableau-only
change will be added here, with the same symptom → Windows behaviour → how-verified header the main
series uses, and this section updated to name it.
