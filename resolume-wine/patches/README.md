# Patches

Two sets, both applied to a pristine `wine-11.18` (the dl.winehq.org tarball).

```
patches/
├── series/                  the consolidated sibling series, 0001..0019
├── sources/                 the untouched source patch dirs of the two sibling projects
├── local/                   this project's own patches (0100…)
└── README.md                this file
```

## `series/` — the AutoCAD-on-Wine base plus the Power-BI-on-Wine additions
`tools/apply_patches.sh <tree>` applies `series/*` then `local/*` in filename order.

| series | from | why |
|---|---|---|
| `0001`–`0014` | `sources/acad-wine-main/` (14 of its patches) | the AutoCAD base: wintrust blob/timestamp verification, `RegLoadAppKey` hive, urlmon zone mapping, session-0 services, Windows `hosts` file, group-policy certificate stores, completion ports, fd-backed pipe semantics, missing exports, `ws2_32` NLA, winex11 stale-window tolerance, `GetUserNameExW`, `msiexec` command line, ntdll actctx `privatePath`. What makes a large Windows installer stack and its UI work. |
| `0015`–`0019` | `sources/powerbi/` (5 of its patches) | WinRT metadata resolution (`wintypes`), `NtImpersonateAnonymousToken`, `secur32` Negotiate/SPNEGO, `LsaFreeReturnBuffer`, `oledb32` `DataConvert` VARIANT I8/BOOL. |

The same two sources the task named ("the wine patches in the autocad and powerbi folders") — copied
here untouched so the working directory is self-contained. `SERIES.tsv`-style provenance is in the
table above; the two projects also carry their own Wine-suite tests (`0007-tests-cover-the-series` in
each source tree), which were deliberately **not** carried over so the build stays lean.

## `local/` — this project's patches

| patch | what | why it was needed |
|---|---|---|
| `0100-dxgi-output-WaitForVBlank.patch` | implements `IDXGIOutput::WaitForVBlank` in `dlls/dxgi` (paces the caller at the output's refresh rate) instead of returning `E_NOTIMPL` | **This is what makes Resolume Arena start.** With the stub, Arena idled after its renderer/GPU-monitor setup with a black window and never reached its UI (`FINDINGS.md` M13) |

### Verification
```sh
mkdir -p /tmp/verify && tar xf wine-11.18.tar.xz -C /tmp/verify
cp -a /tmp/verify/wine-11.18 /tmp/verify/applied
tools/apply_patches.sh /tmp/verify/applied      # series 19/19 OK, local 1/1 OK
```
and `patch -p1 --dry-run -d wine-11.18 -i patches/local/0100-…` against the pristine tree.

## Not a patch, but required at runtime
Arena also needs the Windows core fonts present in the prefix — Wine substitutes Arial/Verdana for
`CreateFont` but does not enumerate them, so the app's font lookup fails. That is a deployment step,
not a code change: **`docs/FONT_REQUIREMENT.md`** and `tools/install_corefonts.sh`
(wired into `tools/mkprefix.sh`).
