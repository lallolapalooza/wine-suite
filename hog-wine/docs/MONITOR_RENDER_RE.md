# Why `monitor-win32-golden.exe`'s `Processor` window is created but never drawn

Agent `HogMonitorRenderRE`. Everything below is measured on this host (patched Wine 11.18,
`state/work/prefix`, display `:2`) against the real Windows 11 guest (`win11`, no GPU, no
HASP key) — see `docs/VM_REFERENCE.md` for the Windows ground truth.

**Verdict (one line):** cause **(a) — the window never receives a paint/expose**: under Wine
the `Processor` HWND is a normal, visible, unoccluded window with a *pending, non-empty update
region*, and the app polls `PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)`, but Wine never hands it
the `WM_PAINT`. The app is not stuck and not waiting on a server/licence/device — the identical
process paints its full UI the instant a paint is delivered by any other route.
**Wine-fixable**: the app asks for nothing but the plain Win32 contract; the failing code is
Wine's server-side paint-message generation (files/functions named in §6).

---

## 1. Reproduction

Two ways, both give the same defect:

* launcher → **Processor** button (the original report) →
  `monitor-win32-golden.exe -port=6600 -netnum=1`;
* the same exe started directly with that argv (what the Windows reference used), e.g.
  `tools/run_hog.sh mon1 --secs 35 --iv 5 --exe monitor-win32-golden.exe -- -port=6600 -netnum=1`.

The top-level window appears (Wine, `winenum.exe list`, run inside the same prefix):

```
hwnd=0x00010074 pid=284 vis=1 class=Qt5151QWindow rect=(415,315)-(1185,685) style=0x96000000 ex=0x00000000 owner=0x00030066 parent=0x00030066 update=1 title='Processor'
hwnd=0x00030066 pid=284 vis=0 class=Qt5151QWindowIcon rect=(473,260)-(1121,774) style=0x86cf0000 ex=0x00000100 owner=0x00000000 parent=0x00000000 update=0 title='monitor-win32-golden'
```

and its contents are never painted: the root capture is only two colours, `#000000` + one
`770x370` white rectangle, OCR finds nothing, and `evidence/hog_processor_wine.png` is a
770x370, 2-colour, 436-byte PNG. The same window on Windows (`evidence/vm_hog_launch_05_processor_crop.png`)
OCRs as:

```
Show Server IP: No Server
Hog Net IP: 192.168.122.230
Fixture Net IP: 192.168.122.230
Port Number: 6600
Software Version: v5.2.1 (b 31)      Offline
```

Zero `err:`/`fixme:` lines that could explain it; the process is alive and its event loop runs.

## 2. Both sides build the *same* window (so this is not a windowing-structure divergence)

Wine, `WINEDEBUG=+relay` scoped (log `logs/api/monrelay.relay.log`), thread `0160`:

```
240862.476:0160:Call user32.CreateWindowExW(0,0365f470 L"Qt5151QWindowIcon",0250e170 L"monitor-win32-golden",86cf0000,633,360,648,514,0,0,0x400000,0)  ret=6ae739e2
240862.488:0160:Call user32.CreateWindowExW(0,025418f0 L"Qt5151QWindow",    0250e170 L"monitor-win32-golden",86000000,575,415,770,370,00030066,0,0x400000,0) ret=6ae739e2
240862.491:0160:Call user32.SetWindowTextW(00010074,035d7200 L"Processor")
240862.493:0160:Call user32.ShowWindow(00010074,00000001)
```

`0x10074` (770x370, `WS_POPUP` + clipsiblings/clipchildren, owner = the hidden
`Qt5151QWindowIcon`) is the `Processor`. Windows, 32-bit IAT tracer (`logs/api/win_mon.log`,
`winenum.exe` dump in `logs/vm/win_mon_status.txt`) — identical shape:

```
246 7296 USER32.dll!CreateWindowExW (arg1=0x30d61b8 /*Qt5151QWindowIcon*/, style=0, x/y/w/h=CW_USEDEFAULT ...)
1753 7296 USER32.dll!CreateWindowExW (arg1=0xa855830 /*Qt5151QWindow*/, arg8=0x1004c8 /*owner*/, arg3=0x86000000, x=0xff y=0xd7 w=0x302 h=0x172)
1918 7296 USER32.dll!ShowWindow (arg0=0x870442, arg1=0x1)
```

```
hwnd=0x00870442 pid=5364 vis=True  class=Qt5151QWindow     rect=(255,215)-(1025,585) title='Processor'
hwnd=0x001004C8 pid=5364 vis=False class=Qt5151QWindowIcon rect=(313,160)-(969,679)  title='monitor-win32-golden'
```

> Note: `docs/VM_REFERENCE.md` records the Windows `Processor` class as `MonitorWindow`. That
> value came from UIAutomation's `AutomationElement.Current.ClassName`, which for a Qt window is
> Qt's accessible class name; the real Win32 class, read with `GetClassNameW`, is
> `Qt5151QWindow` on **both** sides. So there is **no** window-class divergence — the
> `MonitorWindow` name is the app's C++ `QWindow` subclass.

## 3. The messages the window does and does not get

Whole window-proc stream for `hwnd 0x10074` under Wine (`+relay`, `Call window proc …`):

```
WM_NCCREATE WM_NCCALCSIZE WM_CREATE WM_SIZE WM_MOVE WM_WINDOWPOSCHANGING WM_NCCALCSIZE
WM_WINDOWPOSCHANGED WM_SETICON WM_GETICON WM_SETTEXT WM_SHOWWINDOW WM_WINDOWPOSCHANGING
WM_QUERYNEWPALETTE WM_ACTIVATEAPP WM_NCACTIVATE WM_ACTIVATE WM_IME_SETCONTEXT WM_SETFOCUS
WM_NCPAINT WM_ERASEBKGND WM_WINDOWPOSCHANGED
```

**No `WM_PAINT` — not once, in a 30 s capture.** `+msg,+win` (logs/runs/mon4) confirms:
`grep -c WM_PAINT logs/runs/mon4/dbg.log` = **0** for the whole process, and the only messages
ever dequeued for `0x10074` are `WM_WINE_WINDOW_STATE_CHANGED`/`WM_WINE_SETCURSOR`.

Tracer counts (no return values on i386), Wine vs Windows, same exe/argv:

| call | Wine `mon_wine.log` | Windows `win_mon.log` |
|---|---|---|
| `BeginPaint` / `EndPaint` | **0 / 0** | **1 / 1** |
| `GetUpdateRect` | 0 | (not in cfg) |
| `InvalidateRect` / `UpdateWindow` | **0 / 0** | **0 / 0** (patterns present; `RedrawWindow`/`ValidateRect` are not in `hog.cfg`) |
| `CreateWindowExW` | 12 | 8 |
| `ShowWindow` | 1 | 1 |
| `SetPixelFormat` / `ChoosePixelFormat` | 5 / 4 | 1 / 1 |
| `wglCreateContext` / `wglGetProcAddress` | **2 / 1156** | **0 / 0** (guest: no GPU) |
| `SwapBuffers` | 0 | 0 |
| `BitBlt` / `StretchDIBits` | 0 | (not in hog.cfg) |

Windows paints: `2087 USER32.dll!BeginPaint (arg0=0x870442 …) -> ?` … `2632 USER32.dll!EndPaint`.
Wine never enters Qt's paint handler at all — it is not that painting fails, it is that Qt is
never asked to paint.

Wine **can** deliver a first paint for the same kind of Qt raster window in this prefix: the
launcher trace (`logs/api/wine_hog.log`) contains
`18521 296 USER32.dll!BeginPaint (arg0=0x4005e …)` — one paint for `Hog Start`, whose window Qt
created with an explicit request for the final geometry at show time. So §3 is specific to the
monitor window, not a global "Wine never paints" statement.

Also relevant as an *environmental* (not causal) divergence: on Wine Qt's OpenGL probe succeeds
(host GPU) and the monitor creates/uses GL contexts; on the GPU-less guest Windows never loads
`opengl32`. The `Processor` window itself is a raster window on both sides (class has no
`OwnDC` suffix, `GCL_STYLE=0x8=CS_DBLCLKS`, background `COLOR_WINDOW`, and the paint path is
`WM_PAINT` → `QWindowsWindow::handleWmPaint` → `BeginPaint` … `QWindowsBackingStore::flush`
`BitBlt`, Qt 5.15.1 `qwindowswindow.cpp:2066`, `qwindowsbackingstore.cpp:78`).

## 4. The window is a perfectly valid paint target under Wine

`tools/winenum/winenum.exe` (built in-tree, i686, run in the same prefix) against the live window:

* `GetUpdateRgn(hwnd, rgn, FALSE)` — **non-consuming** probe — returns `SIMPLEREGION`
  `box=(0,0)-(770,370)` (the whole client area) *continuously*, every 250 ms, while the app is
  pumping `PeekMessage`. A stale update region + a live message loop + no `WM_PAINT` is exactly
  the defect.
* `ValidateRect(hwnd, NULL)` **does** clear it (`GetUpdateRgn` → `NULLREGION`), i.e. Wine's
  server considers the window *visible* (its `redraw_window()` handler bails out on
  `!is_visible(win)`), so this is not the "hidden/occluded window" case.
* `RedrawWindow(hwnd, NULL, NULL, RDW_INVALIDATE)` re-creates the region — still **no** paint.
* But the **synchronous** routes paint it immediately and completely:
  * `RedrawWindow(hwnd, NULL, NULL, RDW_INVALIDATE|RDW_UPDATENOW|RDW_ERASE|RDW_ALLCHILDREN)`
    (`winenum find Processor`) → the root histogram grows the full grey UI
    (`#333333`, `#5A5A5A`, `#282828`, … — logs/runs/mon2, mon3);
  * `PostMessage(hwnd, WM_PAINT, 0, 0)` (`winenum postpaint Processor`) → same full UI
    (logs/runs/mon11 after.png).

So the app, its Qt event dispatcher, its backing store and its window are all fine; only the
*queued* `WM_PAINT` that Wine is supposed to synthesise for the pending invalid region is
missing. Nothing in the app's own calls consumes the region: the relay shows the monitor makes
**zero** `ValidateRect`/`GetUpdateRect`/`InvalidateRect`/`UpdateWindow`/`RedrawWindow`/
`BeginPaint` calls (so it is not QWidget/Qt "validating without painting").

## 5. It is not (b), (c) or (d)

* **(b) GL scene graph fails** — no: the window is a raster `QWindowsWindow`; forcing a
  `WM_PAINT` renders the entire UI through the ordinary GDI backing-store path.
* **(c) a Wine call returns "cannot render"** — no: `ChoosePixelFormat`/`SetPixelFormat`/
  `DescribePixelFormat`/`wglCreateContext`/`wglMakeCurrent` all succeed early in start-up (they
  are Qt's GL capability probe, not this window); `DwmIsCompositionEnabled` is never reached
  under Wine only *because* the paint never happens (it is inside `handleWmPaint`); no hooked
  call in the render path returns failure and there are no `err:` lines.
* **(d) waiting on server/licence/device** — no: the process polls its queue 44×/s and paints
  instantly when handed any paint message; the Windows guest reference runs the same window
  offline with no server, no licence and no hardware.

## 6. The named cause and the Wine code that owns it

The app's expectation is the plain Win32 contract: a non-minimised, `WS_VISIBLE`, unoccluded
window whose update region is non-empty must be handed `WM_PAINT` by `GetMessage`/`PeekMessage`.
Wine keeps the region (visible through `GetUpdateRgn`) but does not synthesise the message for
this window.

Wine code owning each step (paths relative to `/home/asdf/projects/hog-wine/wine-11.18`):

| step | file · function |
|---|---|
| create/keep the update region (win32u side) | `dlls/win32u/dce.c` · `redraw_window_rects()`, `NtUserInvalidateRect`/`NtUserValidateRect`, `set_update_region()` bookkeeping |
| the "newly shown window" initial repaint | `dlls/win32u/window.c` · `set_window_pos()`, the *"Give newly shown windows a chance to redraw"* block (~line 4197: `erase_now(winpos->hwnd, 0)` — it only emits `WM_NCPAINT`/`WM_ERASEBKGND`; it does not invalidate the client area, so a window shown with `SWP_NOSIZE|SWP_NOMOVE` gets no region from this path) |
| queue `QS_PAINT` / paint count | `dlls/win32u/dce.c` `erase_now()`/`send_ncpaint()` → `dlls/win32u/window.c`… server side `server/window.c: set_update_region()` → `inc_window_paint_count()` |
| **selection + generation of the queued `WM_PAINT`** | `server/queue.c` · `DECL_HANDLER(get_message)`, the *"now check for WM_PAINT"* branch (`queue->paint_count && check_msg_filter(WM_PAINT,…) && find_window_to_repaint(get_win, current)`), selecting via `server/window.c` · `find_window_to_repaint()` → `find_child_to_repaint()` → `win_needs_repaint()` (`win->update_region \|\| PAINT_INTERNAL`) |
| the synchronous paths that *do* work (used by the probes, not by the app) | `server/window.c: update_now()` (RDW_UPDATENOW) and `dlls/win32u/dce.c: NtUserUpdateWindow()` |

The minimal native repro `tools/winenum/showpaint3.c` (same class background, same
`0x86cf0000` owner + hidden owner + `0x86000000` popup, `ShowWindow(SW_SHOWNORMAL)`,
`SWP_FRAMECHANGED` pre-call, self-sent `WM_NCPAINT`) **does** receive its `WM_PAINT` on this
Wine, so the trigger is some piece of per-process/per-window state in the monitor process
(the monitor runs ~12 windows on a single GUI thread plus Qt/WebEngine worker threads). Pinning
the exact bookkeeping fault (queue `paint_count` vs `find_window_to_repaint()` returning NULL,
given the region is known non-empty and the window known visible) needs Wine-internal
instrumentation; this project forbids rebuilding Wine, so that last step is left as the patch
task once a fix is attempted — the above table is where to add the trace/breakpoint.

## 7. Relation to the sibling Power BI "no compositor / occluded surfaces" gap

**Not the same defect, but the same family.** The Power BI gap (`STATE.md`, `docs/PARITY.md`)
is: *an already-painted* window that is occluded and then uncovered is never re-damaged, so it
comes back white — Wine has no compositor/DWM to generate the uncover damage. Here the window
was never painted *once*: it is freshly shown, unoccluded (a full-body `GetUpdateRgn` proves the
region is not cropped away), and the missing message is the initial `WM_PAINT` that Windows
generates for any newly shown window. A fix for one is not automatically a fix for the other,
but both are Wine's window-damage/paint-scheduling being incomplete, and both leave a Hog Qt
surface showing the class background (`COLOR_WINDOW` white).

## 8. Repro artefacts

| artefact | what |
|---|---|
| `logs/runs/mon1/mon_wine.log` | 32-bit IAT trace of the monitor (no `BeginPaint`/`WM_PAINT`-driven calls; GL probe; window creation) |
| `logs/api/monrelay.relay.log`, `monrelay2.relay.log`, `monpeek.relay.log` | scoped `WINEDEBUG=+relay` of the monitor: window class names/styles, `ShowWindow`, the full message stream, and the app's `PeekMessageW(&msg,0,0,0,PM_REMOVE)` |
| `logs/runs/mon4/dbg.log` | `+win,+msg` of the monitor (`grep -c WM_PAINT` = 0) |
| `logs/runs/mon2..mon11` | reproduction + probes (histograms, `winenum` output, `watch`/`val`/`inv`/`postpaint`) |
| `logs/api/win_mon.log`, `logs/vm/win_mon_status.txt` | Windows tracer + `GetClassNameW` dump of the same process (Windows gets `BeginPaint` and paints) |
| `tools/winenum/` | `winenum.exe` (`list`/`class`/`watch`/`val`/`inv`/`poke`/`postpaint`/`classstyle`), `showpaint3.c` minimal repro |
| `tools/apitrace/monitor.cfg` | render-path tracer config used for the Wine capture |

Reproduce in one go:

```sh
source env.sh
# Wine
tools/run_hog.sh mon1 --secs 35 --iv 5 --exe monitor-win32-golden.exe -- -port=6600 -netnum=1
i686-w64-mingw32-gcc -O2 -municode -o tools/winenum/winenum.exe tools/winenum/winenum.c -lgdi32
cp tools/winenum/winenum.exe "$HW_PREFIX/drive_c/"
"$WINEBUILD" 'C:\winenum.exe' watch Processor 12      # region pending, no paint
"$WINEBUILD" 'C:\winenum.exe' postpaint Processor     # paints the full UI
# Windows (guest, elevated)
tools/vm/elev.sh tools/vm/guest_monitor_hog.ps1       # win_mon.log + GetClassNameW window dump
```
