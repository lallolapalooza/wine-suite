# Patches

The series applies in order to a pristine `wine-11.18.tar.xz` (dl.winehq.org):

```
tar -xf wine-11.18.tar.xz && cd wine-11.18
for p in ../patches/*.patch; do patch -p1 -i "$p"; done
```

`wine-11.18/` in this repository is shipped with the whole series already applied — the loop is
only for starting from a fresh tarball. Every patch is against unmodified upstream source and
carries its own header: the symptom, the Windows behaviour it restores, and how it was verified.

## Provenance

`0001`–`0016` are the base series of the AutoCAD fork (`acad-wine-main`), copied unchanged. They
are what makes the Autodesk ODIS 2027 installer stack work under Wine: the loader/`actctx`
`privatePath` probe, the Windows hosts file, the group-policy/enterprise cert stores, session-0
services, fd-backed pipe semantics, completion ports, the `msiexec` command line, the missing
exports the licensing/browser stacks probe for, and the X11 stale-window tolerance the WPF UI
needs. See the AutoCAD project's FINDINGS for the evidence behind each.

Two of that fork's patches are deliberately **not** here: `0005` (bcrypt key/plaintext dump) and
`0011` (user32 licence-error caller dump) are debug-only hooks, not fixes.

## Numbering

Keep the AutoCAD numbers for the copied ones so the two repositories can be diffed directly;
new Revit-specific patches continue from `0100` to make it obvious at a glance which are local.

| # | subject | why |
|---|---|---|
| 0100 | ncrypt: import ECC key blobs | Revit 2027's startup self-test in `PersistenceDB.dll` (`DataIntegrity.cpp:47`) imports a hard-coded ECDSA P-256 key with `NCryptImportKey(..., L"ECCPRIVATEBLOB", ...)` and treats failure as fatal; Wine's `ncrypt` only knew the RSA magics (`Unhandled key magic 0x32534345`) although `bcrypt` already implements the ECC import. Test: `dlls/ncrypt/tests/ncrypt.c::test_key_import_ecc`. |
| 0101 | dcomp: device/target/visual objects, `Commit`, composition surface path | Revit's WebView2 licensing dialog is blank under stock Wine: `dcomp.dll` was three `E_NOTIMPL` stubs while both Autodesk's host and the WebView2 runtime drive DirectComposition directly (`CreateTargetForHwnd` → `CreateVisual`/`AddVisual` → `SetRoot` → `SetContent` → `Commit`, and Chromium kills its GPU process if `IDCompositionVisual3` is not answered). Test: `dlls/dcomp/tests/dcomp.c`. |
| 0102 | dxgi: composition swapchain, per-present compositing, GDI-compatible buffers | The next call after `SetRoot` is `IDXGIFactory2::CreateSwapChainForComposition` (was a stub → GPU process died and relaunched 6×), and Chromium rasterises the page with GDI into the swapchain back buffer (`IDXGISurface1::GetDC`, semi-stub). `ResizeBuffers(flags=0)` also dropped `WINED3D_TEXTURE_GET_DC`, which made the dialog blank in some runs and painted in others. |

## Every patch brings a test

A patch that changes Wine code is only accepted into this fork together with a test in the matching
`dlls/<module>/tests/` suite, wired into `START_TEST`, and the run of that suite is the evidence
recorded for it — exactly how `0016` ships `kernel32/tests/actctx.c::test_private_path` (upstream
MR !10753) and how the AutoCAD fork verified it (3298 tests executed, 0 failures, plus a
`WINEDEBUG=+actctx` trace showing the probe hit).

Reproduce any module's suite with:

```
tools/run_wine_tests.sh --list                 # which modules the patches touch
tools/run_wine_tests.sh kernel32 actctx        # build + run dlls/kernel32/tests under this fork
```

The runner builds out of the build tree, runs under `wine-install/bin/wine` in a scratch prefix and
writes `$REVIT_LOGS/tests/<module>[_<args>].log`.

## Not patches

Two Revit-specific gaps are **not** Wine defects and so are tools, not patches:

* the ADIX/MSIX post-install actions that need PowerShell (`tools/neutralize_postinstall.py`
  removes them from the package manifests) — nothing for Wine to do; the prefix has no PowerShell;
* the licensing registration fallback (`tools/fix_licensing_registration.sh`) — application
  configuration, identical in kind to the AutoCAD fork's own registration script.
