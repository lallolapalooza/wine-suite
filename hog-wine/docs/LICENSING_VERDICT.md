# Licensing verdict — Hog PC 5.2.1.31 under Wine

**Short answer: nothing is blocked.** The owner's rule was *«if the app can't run or does run but can't be
licensed because wine lacks kernel-level APIs, then say so, document it and stop»*. Hog PC **runs**, and
its licensing model is *selective by hardware* — the base application needs no key at all, on Windows or
under Wine. So there is no kernel-level licensing wall to hit for the functionality this project targets,
and no reason to stop.

## What the product's licensing actually is
The package ships Sentinel HASP (`haspdinst.exe`) and declares `HASPEXISTS` among its
`SecureCustomProperties`, and the MSI runs an `AppSearch` on the `HaspVersion` signature. But:

- Under `/qn` the HASP driver installer **is never run** (`Install_HASP`/`Enable_HASP` are declared but
  not scheduled in the sequence).
- On the Windows reference the launcher comes straight up **with no licence dialog, no HASP error and no
  demo nag**, and the offline processor runs ("Start Processor" → `monitor-win32-golden.exe`, window
  `Processor`: `Show Server IP: No Server`, `Port Number: 6600`, `Offline`, `Software Version: v5.2.1
  (b 31)`).
- On Windows the guest's HASP *driver* happened to be present (9.16.156120.1) from an earlier product,
  yet the install and run behave identically — the driver is not what unlocks start-up.

That matches the owner's description: **additional functionality unlocks when connected to lighting
hardware** (which carries a licence dongle), the same selective pattern as ETC's other products — the
*base* console/offline software runs unlicensed.

## What happens under Wine
Identical in kind, with no licence interaction at all:
- MSI installs (rc 0); launcher `Hog Start` 792x338 appears; `New Show` creates the show files; the
  launcher spawns `server-win32-golden` (listening on 6600) and `desktop-win32-golden`; the console
  window `Hog PC - Primary Screen` renders; `Start Processor` spawns `monitor-win32-golden` and the
  `Processor` window 770x370.
- **Zero `err:` lines** in the run; the only HASP-related work is the `AppSearch` on a signature that can
  simply miss (the property stays unset, nothing gates on it).
- `setupapi:DiInstallDriverA` is a Wine stub (`dlls/newdev/main.c:154`, returns TRUE and installs
  nothing) — this is the **only** licence/hardware-adjacent gap, and it affects installing the USB
  *hardware* drivers for attached consoles, not the application.

## Where a kernel-level wall *would* appear (not hit here)
If the target were "run Hog PC as if attached to a real console/DP8000", the HASP dongle inside that
hardware would need the Sentinel kernel driver, which Wine cannot load — the same architectural wall the
Mastercam project documented for CodeMeter. That is out of scope for this project's goal (open the
application and behave like a standalone Hog PC), and the app needs no driver to do so.

## Conclusion
- App runs: **yes** (launcher, show creation, server + desktop console UI, offline processor).
- Licence needed for that: **no** — same as Windows.
- Blocked by Wine kernel-level gaps: **no**.
- Wine patches required to get here: none beyond the carried base (`patches/README.md`); the divergences
  the API diff found are cosmetic/degradation only (`docs/API_DIFF.md`).
