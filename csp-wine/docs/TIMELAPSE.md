# Timelapse / animation export (AppDB issue 2)

> "Exporting timelapses does not work; the current workaround only outputs files with headers
> and nothing else."

## What is known

`patches/local/candidates/0100-mf-encoder-support.patch` (from parka6060/CSPenguin-Installer, author
eninabox) is the community fix. It lives under `candidates/` because it is **not applied by
default** — see `candidates/README.md`. Its upstream form is unusable as-is:

* It is **syntactically broken** — 15 of 21 hunk headers disagree with their bodies, so `patch(1)`
  refuses it (`malformed patch at line 30`). `tools/fix_patch_hunks.py` rebuilds the headers from
  the bodies; the repaired copy is `patches/local/candidates/0100-mf-encoder-support.patch`.
* It was written against **Wine 11.4**, and 11.18 has changed underneath it. Applied to 11.18,
  14/21 hunks apply. Of the 7 rejects:
  * `sink_writer_BeginWriting`, `sink_writer_get_buffer_length`, `sink_writer_write_sample`,
    `sink_writer_WriteSample` rejects are the author's own `TRACE`/`WARN` diff noise — 11.18
    already matches the patch's *result* for the latter two, so those are no-ops.
  * `sink_writer_SetInputMediaType`'s reject is obsolete: 11.18 already implements the
    converter-then-encoder fallback through `stream_create_transforms(..., BOOL use_encoder, ...)`
    and `create_encoder_transform()`.

Still genuinely missing in 11.18 (the real remaining delta):

| site | 11.18 state | patch provides |
|---|---|---|
| `dlls/mfplat/main.c` `bytestream_file_Close` | `FIXME` + `E_NOTIMPL` | flush + `CloseHandle`, return `HRESULT_FROM_WIN32` |
| `dlls/winegstreamer/media_sink.c` `media_sink_SetPresentationClock` | `FIXME` stub, returns `E_NOTIMPL` | add/remove the clock state sink, handle `MF_E_SHUTDOWN` |
| `dlls/winegstreamer/wg_transform.c` `align_video_info_planes` | only an NV12 fix-up flag | additional I420/YV12 plane fix-up flag |
| `dlls/mfreadwrite/writer.c` | — | `SINK_WRITER_STATE_FINALIZED` state handling |

## Plan (evidence first, patch second)

The instruction for this project is to let the application tell us what it needs, rather than
resurrecting 11.4-era code:

1. Build and boot CSP on the patched Wine.
2. Create a timelapse and export it (the AppDB symptom: output file has a header only).
3. Capture the failing calls:
   * `WINEDEBUG=+mfplat,+mfreadwrite,+winegstreamer,+relay` on Wine,
   * the same operation on the Windows guest as the reference,
   * `tools/relaydiff.py wine-log` / `tools/api_retval_diff.py` to reduce the two to the calls
     whose results differ.
4. Write the **minimal** patch for 11.18 at the site the difference points to (most likely
   `bytestream_file_Close` first: an unflushed/unclosed byte stream explains "header only").
5. Verify: exported file contains frames, plays, and matches the Windows reference's frame count
   and duration for the same project.

## Fallback (documented, not a patch)

If a source patch cannot be made to work in reasonable time, CSPenguin's shipped approach is fully
reproducible and must then be documented here as the supported fix: replace the Media Foundation
DLLs in the prefix with their prebuilt ones and set overrides.

```
patches/x86_64-windows-wine11.4/{mfplat,mfreadwrite,winegstreamer}.dll -> <prefix>/drive_c/windows/system32/
patches/x86_64-unix-wine11.4/winegstreamer.so                        -> <wine install>/lib/wine/x86_64-unix/
HKCU\Software\Wine\DllOverrides: mfplat=native,builtin ; mfreadwrite=native,builtin
```

Caveat stated by the author: "Wine updates require an exact matching timelapse patch set" — the
DLLs are version-locked to the Wine build, which is exactly why a source patch is preferred here.
