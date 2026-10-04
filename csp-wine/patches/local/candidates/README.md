# Candidate patches — NOT applied by default

`tools/apply_patches.sh` applies only `patches/series/*.patch` and
`patches/local/*.patch` + `patches/local/dcomp-staging/[0-9]*.patch`. Files in this `candidates/`
directory are deliberately **excluded**: they do not apply cleanly on their own, or they are not yet
justified by an observed failure.

## `0100-mf-encoder-support.patch`

Media Foundation sink-writer/encoder work for **timelapse/video export**, from
`parka6060/CSPenguin-Installer` (author eninabox). Two things to know:

1. **Upstream's file is syntactically broken** — 15 of its 21 hunk headers disagree with their
   bodies, so `patch(1)` refuses it (`malformed patch at line 30`). `tools/fix_patch_hunks.py`
   recomputes the headers from the bodies; this file is the repaired result.
2. **It was written against Wine 11.4 and this tree is 11.18.** Applied to a pristine 11.18 it
   applies 14/21 hunks and fails 7 — verified, that is why `tools/apply_patches.sh --check` is
   expected to report exactly one FAIL with this directory present. The rejects are either the
   author's own debug-`TRACE` diff noise or code 11.18 has since refactored
   (`stream_create_transforms(..., BOOL use_encoder, ...)` and `create_encoder_transform()` already
   exist; `sink_writer_get_buffer_length`/`sink_writer_WriteSample` already match the patch's
   result). The real remaining delta is `bytestream_file_Close` (still `FIXME`/`E_NOTIMPL` in 11.18),
   `media_sink_SetPresentationClock` (still a stub) and the `wg_transform` I420/YV12 plane flag.

Path forward: reproduce the export failure on a licensed session, then patch the site the failure
names. Analysis and the documented non-patch fallback: `docs/TIMELAPSE.md`.
