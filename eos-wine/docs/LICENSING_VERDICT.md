# Licensing verdict — ETC Eos Family v3.3.10.28 under Wine

**Short answer: not applicable — the app runs and needs no licence.** The owner's rule was *«if the app
can't run or does run but can't be licensed because Wine lacks kernel-level APIs, then say so, document
it and stop»*. Here the app **runs**, and the functionality it is meant to have without a key is exactly
what we get — the same as on Windows. Nothing is blocked by a kernel-level API gap, so there is nothing
to stop for.

## What the product's licensing actually is
The vendor bundle ships `haspdinst.exe` (Sentinel HASP/LDK) and the Windows reference confirms the bundle
installs *Sentinel LDK* (`hasplms` service present). `Eos.exe` statically links the Sentinel LDK runtime.
A key is therefore *supported*, but the product is explicitly usable without one: the Windows reference's
launch flow is

```
ETC_LaunchOffline.exe  ->  "Please select your console mode"  ->  launcher (Offline w/viz, Backup
                            DISABLED, Mirror, Offline, Augment3d Tether, Settings)
                       ->  Offline  ->  Eos.exe  ->  full editor
```
with `ETCNomad, MultiConsole Mode=Offline, UserID=1, Device Status Offline, [EOS] OfflineOutputEnable=0`.
**No demo/activation/key dialog appears anywhere** on Windows.

## What happens under Wine
Identical in kind: `Eos.exe` starts, `ACN started`, the editor window `Eos : 1` (1600x1000) comes up and
renders its UI (OCR evidence in `evidence/eos_editor_wine.png` / `.ocr.txt`), and `eos.ini` records the
same offline console state. No licence prompt, no licence failure, no blocked path.

The Sentinel runtime is present but never on a critical path that requires a kernel driver: the parts of
the Mastercam experience that *were* architectural (CodeMeter's device-gated `Global\CmApiCallIn`, the
Wibu/HASP **kernel drivers** that Wine cannot load) do not arise here, because Eos's offline mode does not
need a dongle to reach the editor.

## If a key is ever wanted
The vendor's HASP/LDK stack installs its service through Wine (see the Mastercam project's findings for
the service-token work that makes vendor services start: our `patches/local/0101-services-service-logon-token.patch`).
A **network** licence (`hasplms`, TCP/UDP 1947) is the only path that could be exercised without kernel
driver support, exactly as in the Mastercam verdict. This was **not** attempted, because the app is fully
usable without it and the owner's goal is the unlicensed offline editor.

## Conclusion
- App runs: **yes** (editor window, UI rendering, `ACN started`, stable for 150 s+).
- Licence needed to run: **no** — same as Windows.
- Blocked by Wine kernel-level gaps: **no**.
- Reproducible setup steps to reach Windows parity: `docs/SLP_PORT_FIX.md` (ETC SLP component +
  privileged-port capability) and `patches/local/0102-*` (iphlpapi change notifications).
