# Patches

The working directory carries the patch series **and** the patches it was collected from.

```
patches/
├── series/     the consolidated series, 0001..0022 — this is what gets applied to pristine Wine
├── SERIES.tsv  series file  ->  source repo  ->  source patch   (the provenance map)
└── sources/    the untouched patch directories of the four sibling projects, as found:
                powerbi-linux/  autocad2027-private-main/  acad-wine-main/  revit-wine-main/
```

## How `series/` was assembled

The application base is `wine-11.18.tar.xz` from dl.winehq.org — the same base every sibling
project uses, so their patches apply unchanged. The series is the union:

| series | from | why |
|---|---|---|
| `0001`–`0014` | `acad-wine-main/patches/0001..0016` (14 of them) | the AutoCAD base series: wintrust / regf hive / urlmon zone / session-0 services / Windows `hosts` / group-policy cert stores / completion ports / fd-backed pipe semantics / missing exports / ws2_32 NLA / winex11 stale-window tolerance / `GetUserNameExW` / `msiexec` command line / ntdll actctx `privatePath`. What makes a large Windows CAD installer stack and its WPF UI work under Wine. |
| `0015`–`0019` | `powerbi-linux/patches/0001,0002,0003,0004,0006` | WinRT metadata resolution (`wintypes`), `NtImpersonateAnonymousToken`, `secur32` Negotiate/SPNEGO, `LsaFreeReturnBuffer` NTSTATUS, `oledb32` VARIANT I8/BOOL. |
| `0020`–`0022` | `revit-wine-main/patches/0100,0101,0102` | `ncrypt` ECC key blobs; **`dcomp` device/target/visual/Commit implementation**; **`dxgi` composition swapchain + `IDXGISurface1::GetDC`**. The graphics patch pair. |

Deliberately **not** included:

* `autocad2027-private-main/patches/0005-bcrypt-debug-dump.patch` and
  `0011-user32-debug-licence-hooks.patch` — debug-only hooks, not fixes (the Revit repo's own
  README says the same about them).
* `powerbi-linux/patches/0005-secur32-GetUserNameExW-…` — the same change as acad `0014`; applying
  both conflicts. Verified equivalent: the `+`/`-` lines of the two patches are identical, and
  only `dlls/secur32/secur32.c` is touched by either.

## Verification (run, not assumed)

```sh
mkdir -p /tmp/verify_series && tar xf wine-11.18.tar.xz -C /tmp/verify_series
cp -a /tmp/verify_series/wine-11.18 /tmp/verify_series/applied
tools/apply_patches.sh /tmp/verify_series/applied          # 22/22 OK
```

and every one of the 46 files the series touches is **byte-identical** between
`/tmp/verify_series/applied` and the build tree `wine/wine-11.18` (which was patched
independently, one patch at a time, as it was being set up).

`tools/apply_patches.sh <tree> [--dry-run]` re-runs it against any tree.

## Adding a Solid-Edge-specific patch

Continue the numbering from `0023`. Keep the upstream style used by every sibling project: a
prose header naming **the symptom, the Windows behaviour it restores, and how it was verified**,
then the unified diff.
