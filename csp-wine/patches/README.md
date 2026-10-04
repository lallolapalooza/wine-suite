# Wine patches used to run CLIP STUDIO PAINT 5.1.4 on Linux

Base: **Wine 11.18** (`wine-11.18.tar.xz` from dl.winehq.org).

Two directories. The split is the answer to "which patches are exclusive to this app".

```
patches/
  series/                 shared base — AutoCAD-on-Wine (14) + Power BI-on-Wine (5) = 0001..0019
  local/                  patches that exist *because of this app* (CLIP STUDIO PAINT)
    dcomp-staging/        the 67-patch wine-staging DirectComposition set
    candidates/           NOT applied by default (see candidates/README.md)
```

Applied, in this order, by `tools/apply_patches.sh`:

```
1. patches/series/0001..0019
2. patches/local/*.patch          (none at present)
3. patches/local/dcomp-staging/[0-9]*.patch  (0067 files)
```

Verified from a **pristine** `wine-11.18.tar.xz`: **86 OK, 0 FAIL** (`logs/patch_check3.log`).
`--check` extracts the tarball into a scratch directory and applies the whole series there for real;
it does not dry-run each patch against an unpatched tree, which cannot work for a cumulative series.

## `patches/series/` — shared base, NOT specific to CSP

Nineteen patches carried over from the AutoCAD-on-Wine and Power BI-on-Wine work, applied on
request as the common base for this project. They are general Wine-API fixes
(wintrust RFC3161, RegLoadAppKey, urlmon zones, session-0 services, hosts file, crypt32 group
policy stores, overlapped completion info, fd-backed pipes, missing exports, NS_NLA lookups,
winex11 stale-window errors, `GetUserNameExW`, msiexec command-line parsing, activation-context
probing, WinRT metadata resolution, `NtImpersonateAnonymousToken`, SPNEGO `Negotiate`,
`LsaFreeReturnBuffer`, `oledb32` `IDataConvert` I8/BOOL), each with its own tests patch.

They apply cleanly and in order: 19/19 OK against a pristine 11.18 tarball.

**Not CSP-exclusive.** Removing them would not be expected to break CSP specifically.

## `patches/local/` — exclusive to CLIP STUDIO PAINT

### `dcomp-staging/` — 67 patches, DirectComposition implementation

Provenance: `wine-staging`, tag **v11.18**, patchset `dcomp-DCompositionCreateDevice2`
(`gitlab.winehq.org/wine/wine-staging`). Downloaded verbatim; `definition` carries the upstream
provenance chain (zhiyi's tree, MR !9839, bug 59631) and states:

```
Fixes: [54968] dcomp: Implement DCompositionCreateDevice2
Fixes: [58315] Clip Studio Paint 4 menus turn black when clicked
```

That is an explicit statement that this patchset exists to fix CLIP STUDIO PAINT's black
menus/settings/login panels (WineHQ bug 58315) — the reason it is filed under `local/` and not
`series/`, even though the code is upstream staging.

State: **67/67 applied cleanly** to `series + wine-11.18` (verified in `state/scratch/wine-patchtest`).
It adds `dlls/dcomp/{visual,surface,target}.c`, a private header + IDL, dcomp tests, and a
`dlls/dxgi/factory.c` HACK for `CreateSwapChainForComposition`.

Upstream calls it a HACK patchset: a complete implementation would want a `dwm.exe` plus graphics
driver integration; this one drives composition through d3d11/dxgi in-process.

### `candidates/0100-mf-encoder-support.patch` — Media Foundation sink-writer/encoder (timelapse export)

Lives in `patches/local/candidates/` and is **not applied by default**: it is the same stale 11.4-era
patch described below and would break a fresh build. Kept because it is the best available starting
point for the export issue. Full write-up: `candidates/README.md`; plan: `docs/TIMELAPSE.md`.

Provenance: `parka6060/CSPenguin-Installer`, `patches/wine-mf-encoder-support.patch`
(author: eninabox). Purpose: make **timelapse/video export** work — CSP produces files with
headers and no frames without it.

Two problems with the upstream file, both handled here:

1. **The upstream patch is syntactically broken.** 15 of its 21 hunk headers disagree with their
   hunks; `patch(1)` refuses with `malformed patch at line 30`. The bodies are complete, so
   `tools/fix_patch_hunks.py` recomputes the headers from the bodies, producing the file here.
2. **It was written against Wine 11.4 and 11.18 has moved on.** Applied to 11.18: 14/21 hunks
   apply. The 7 rejects are
   * the author's own debug `TRACE`/`WARN` diff noise (no functional change), or
   * code upstream has since refactored: `dlls/mfreadwrite/writer.c` already has
     `stream_create_transforms(..., BOOL use_encoder, ...)` and
     `sink_writer_get_buffer_length`/`sink_writer_WriteSample` already match the patch's result.

   The genuinely still-missing pieces in 11.18 are
   `bytestream_file_Close` (still `FIXME` + `E_NOTIMPL`), `media_sink_SetPresentationClock`
   (still a stub) and the `wg_transform` I420/YV12 plane-fix flag.

**Status: candidate, deliberately not applied by default.** See `docs/TIMELAPSE.md` — the
intended path is to reproduce the export failure on the built Wine, capture the real failing
calls, and write the minimal correct patch for 11.18 rather than resurrecting 11.4-era code.
CSPenguin's alternative (documented, reproducible, not a patch) is to drop their prebuilt
`mfplat.dll`, `mfreadwrite.dll`, `winegstreamer.dll` + unix `winegstreamer.so` into the prefix
with `native,builtin` overrides for `mfplat`/`mfreadwrite`.

## Verifying a tree

```bash
tools/apply_patches.sh --check      # extract pristine tarball to scratch, apply the whole series
                                    # -> 86 OK / 0 FAIL for this set
```

## Applying

```bash
tools/apply_patches.sh              # apply series + local to sources/wine/wine-11.18
```

`tools/apply_patches.sh` is idempotent for genuinely re-runnable patches: a patch whose changes are
already present is reported `SKIP` rather than failing. Note that for a *cumulative* series (patch N
depends on 1..N-1 having been applied) `SKIP` detection is unreliable — the honest test is `--check`
on a pristine extraction, which is what it does.
