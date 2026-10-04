# Next steps, and the licensing blocker

## What is already done

CSP 5.1.4 **installs and opens** on the locally built patched Wine 11.18 and renders the same
surfaces Windows does (first-run Privacy Settings dialog verbatim; the WebView2 start page; the
"Log into Clip Studio" form). See `FINDINGS.md` §4-§6.

## The blocker

The three AppDB issues for this version are all **interactive canvas features**:

1. a new 3D layer flickers erratically after importing an object, until the layer is deselected;
2. timelapse export writes a file with headers and no frames;
3. rotating text makes the text disappear.

Exercising any of them requires the editor, and CSP 5.1.4 gates the editor behind a Clip Studio
account. The start page offers only **View plans** and **Already have a plan?**; the sign-in form
asks for an email and password, and account creation needs email verification. No offline or
trial-without-account path appears on the start page. Nothing here is a Wine defect — the login UI
itself renders and accepts input correctly under Wine (`evidence/wine_csp_login_page.png`).

## Options

**A. Supply a Clip Studio account (or a licence file) that can be used in the prefix.**
This unblocks everything else. With a session, the plan is:
1. Reproduce each issue under Wine and confirm it still occurs on this build (the dcomp patch set
   may already have changed issue-adjacent behaviour — the AppDB reports were made against wine 11.4,
   before the dcomp work landed).
2. For each, capture `WINEDEBUG=+relay`/`+dcomp`/`+mfplat`/`+wined3d` on Wine and the same operation
   on the Windows guest, reduce both with `tools/relaydiff.py` / `tools/api_retval_diff.py`, and
   patch the call whose result differs.
3. Issue 2 has a known starting point: `patches/local/0100-mf-encoder-support.patch` plus
   `docs/TIMELAPSE.md`, which already narrows the missing 11.18 code to four sites
   (`bytestream_file_Close`, `media_sink_SetPresentationClock`, the `wg_transform` I420/YV12
   flag, and the writer `FINALIZED` state).

**B. Static route, no session.** Disassemble/decompile the relevant code paths
(`CLIPStudioPaint.exe` plus its Qt/plugin DLLs; the MF encoder path is in-box Wine code, so the
timelapse issue can be reasoned about from the Wine side alone) and write patches from the code
rather than from observed failures. This can produce candidate patches, but they cannot be verified
as "fixed" without running the feature — and this project's rule is to base patches on observed
failures, so anything produced this way would be labelled unverified.

**C. Stop at verified parity.** The deliverable already covers "installs and opens exactly like
Windows" plus the reproducible recipe and the patch set, with the three issues documented as
requiring a licence.

## What is NOT needed

* No Wine kernel-level API is missing for this app to open: the editor process runs, creates its
  DXGI/DirectComposition surfaces and renders its UI. The blocker is an account, not Wine.
* `docs/TIMELAPSE.md` §"Fallback" records CSPenguin's prebuilt-DLL approach for the export issue;
  it is a documented, reproducible fallback but version-locked to its Wine build, so the source
  patch path (A.3) is preferred.
