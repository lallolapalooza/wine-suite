# `0103-win32u-initial-client-paint.patch` — the first `WM_PAINT` of a newly shown window

Fixes Hog PC's `monitor-win32-golden.exe` **`Processor`** window, which Wine shows but never
paints (`docs/MONITOR_RENDER_RE.md`).

## 1. What is measured

* Wine delivers the whole window-proc stream for the `Processor` HWND
  (`WM_NCCREATE … WM_SHOWWINDOW … WM_NCPAINT WM_ERASEBKGND WM_WINDOWPOSCHANGED`) but **never a
  `WM_PAINT`**; `BeginPaint`/`EndPaint`/`GetUpdateRect`/`InvalidateRect`/`UpdateWindow`/
  `RedrawWindow` are all `0` in a 30 s IAT capture and the window stays at the class background
  (`COLOR_WINDOW`, white).
* The window is a legitimate paint target: it is visible, unoccluded, and
  `GetUpdateRgn(hwnd,rgn,FALSE)` keeps returning `SIMPLEREGION box=(0,0)-(770,370)` (the whole
  client) while the application pumps `PeekMessage(NULL,0,0,PM_REMOVE)`.
* The **synchronous** routes paint it at once and completely: `RedrawWindow(RDW_INVALIDATE|
  RDW_UPDATENOW|RDW_ERASE|RDW_ALLCHILDREN)` and `PostMessage(hwnd,WM_PAINT,0,0)` both produce
  the full UI. Only the *queued* path is broken.
* Windows runs the same `exe`/`argv` and gets `BeginPaint` + `EndPaint` once, i.e. the window's
  client area is painted once as part of being shown.

## 2. Why the queued `WM_PAINT` never arrives

Wine's server synthesises `WM_PAINT` in `server/queue.c:DECL_HANDLER(get_message)`, and that
branch sits **after** sent messages, posted messages, hotkeys, quit and hardware input:

```
    /* then check for posted messages */
    if ((filter & QS_POSTMESSAGE) && get_posted_message(...)) return;
    ...
    /* now check for WM_PAINT */
    if ((filter & QS_PAINT) && queue->paint_count && check_msg_filter(...) &&
        (reply->win = find_window_to_repaint( get_win, current ))) { ... }
```

`WM_PAINT` therefore has the lowest priority and is only ever produced when the thread's queue
is otherwise empty (this matches Windows' documented order: sent, posted, input, `WM_PAINT`,
`WM_TIMER`). The queued path was not instrumented (the project forbids rebuilding Wine to add
traces), but the client-side capture answers the question directly: in the monitor's
`+relay` capture the outer `PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)` returned a message
**3407 times and `0` (queue empty) zero times**.

So `get_message()` was never reached with an empty queue and the `WM_PAINT` branch was never
entered, no matter how long the (pending, non-empty) update region sat there. That is why the
region persists and `RedrawWindow(RDW_INVALIDATE)` changes nothing: re-invalidating cannot make
the queue drain. On Windows the same app does get the paint — its first paint happens as part of
showing the window (the Win32 tracer shows `BeginPaint` right after `ShowWindow`), before the
application's own event traffic can starve it.

## 3. Where Windows semantics differ

`dlls/win32u/window.c:set_window_pos()` already has a block for exactly this transition:

```c
        /* Give newly shown windows a chance to redraw */
        if (((winpos->flags & SWP_AGG_STATUSFLAGS) != SWP_AGG_NOPOSCHANGE)
                && !(orig_flags & SWP_AGG_NOCLIENTCHANGE) && (orig_flags & SWP_SHOWWINDOW))
        {
            erase_now(winpos->hwnd, 0);
        }
```

but `erase_now()` only sends `WM_NCPAINT` / `WM_ERASEBKGND` (both are visible in the measured
stream) and leaves the client paint to the queued `WM_PAINT` that, as shown above, may never be
delivered. The block never calls `NtUserRedrawWindow`/`redraw_window_rects`, so **the client
area of the newly shown window is not invalidated or painted by this path**.

Note on the condition: `fixup_swp_flags()` (`dlls/win32u/window.c`) clears `SWP_SHOWWINDOW`
when the window is already visible (`if (win->dwStyle & WS_VISIBLE) winpos->flags &=
~SWP_SHOWWINDOW;`), so the condition fires on a genuine hidden → visible transition, not on
every `SetWindowPos(SWP_SHOWWINDOW)` of an already-visible window. The server side
(`server/window.c:set_window_pos()`) also invalidates newly exposed windows through
`expose_window()`, but that only leaves the *queued* region described above.

## 4. The fix

In `set_window_pos()`, when the window is newly shown, invalidate its whole client area and
update it right away instead of only erasing it:

```c
    if (need_update)
    {
        /* A window that is being shown has no valid contents yet, and Windows paints it as part
         * of the show.  Invalidate the whole client area and paint it now; the queued WM_PAINT
         * alone is not reliable, since it is only generated when the message queue is otherwise
         * empty and an application with a busy event loop (e.g. Qt reposting wakeup messages)
         * may never let it be delivered, leaving the window permanently unpainted. */
        NtUserRedrawWindow( winpos->hwnd, NULL, NULL, RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW );
    }
```

placed after `WM_WINDOWPOSCHANGED` has been sent, so the window has its final geometry before it
paints. `RDW_INVALIDATE` covers the case where no pending client region was left behind;
`RDW_UPDATENOW` sends the `WM_PAINT` synchronously (the same path
`RedrawWindow(RDW_UPDATENOW)` uses, which is known to paint this window); `BeginPaint` inside
the handler does the `WM_NCPAINT`/`WM_ERASEBKGND` and EndPaint validates the region, so there is
no second, queued paint.

Only the window being shown is touched (no `RDW_ALLCHILDREN`), and only on a real visibility
transition — it is a targeted first paint, not a blanket redraw.

## 5. Windows behaviour restored

A window that is shown and has never been painted is fully invalid and gets its first
`WM_PAINT` (`BeginPaint`/`EndPaint`) as part of being shown, before the application's message
loop can starve it. Windows does this for the same process/argv; Wine now does too.

## 6. How to verify

Build with the patch applied (`tools/apply_patches.sh wine-11.18` picks up
`patches/local/0103-*` by filename, then `tools/build_wine.sh`), then:

1. **Hog** — run the monitor as in `docs/MONITOR_RENDER_RE.md` §1:
   ```sh
   source env.sh
   tools/run_hog.sh mon1 --secs 35 --iv 5 --exe monitor-win32-golden.exe -- -port=6600 -netnum=1
   ```
   The `Processor` window should now show the grey UI (server IP / fixture IP / port / version),
   `evidence/hog_processor_wine.png` should no longer be a two-colour 436-byte PNG, and the
   monitor's IAT/`+relay` capture should contain `BeginPaint`/`EndPaint` (and `WM_PAINT`) for
   the `Processor` HWND instead of 0.
2. **Minimal app** — a Win32 app that creates a window and calls `ShowWindow(SW_SHOWNORMAL)`
   must receive `WM_PAINT` (`tools/winenum/showpaint3.exe <mode>` prints `paints=…`; run it in
   the Hog prefix). The paint now happens during `ShowWindow`, so the counter is non-zero
   without needing the message loop to drain.
3. Probe helper (unchanged): `winenum.exe watch Processor` should stop showing a permanently
   pending region with no paint; with the fix the first `WM_PAINT` is delivered at show time.

## 7. What to watch for when testing

* **Reentrancy** — the `WM_PAINT` is now sent from inside `SetWindowPos`/`ShowWindow`, so the
  window proc runs while the show call is still on the stack. Wine already sends
  `WM_NCPAINT`/`WM_ERASEBKGND`/`WM_WINDOWPOSCHANGED` synchronously from the same place, and
  Windows paints a newly shown window at the same point, but a window proc that assumes no
  `WM_PAINT` until the message loop runs could misbehave. Watch for asserts/crashes in
  `QWindowsWindow::handleWmPaint` if Qt is not fully initialised.
* **Windows created already visible** — `CreateWindowEx(WS_VISIBLE)` goes through the same
  block at the end of creation; the paint then also happens during creation. If a class
  misbehaves there, restrict the new call to windows that already exist (not created in this
  call).
* **Double paint** — `BeginPaint` validates the region, so the queued `WM_PAINT` should not
  follow. If a window's proc does not call `BeginPaint` (ignores `WM_PAINT`), the queued paint
  may still be produced later; that is the normal Win32 contract.
* If the goal is strictly "keep the queued path and only invalidate", note that the evidence in
  §2 shows that alone does not paint this window: the queue never empties.

## 8. Validation performed

* `patch -p1 --dry-run` of `patches/local/0103-win32u-initial-client-paint.patch` on a fresh
  copy of the current patched base (`state/tmp/0103/base`, a copy of `wine-11.18` with
  `patches/series/*` + `patches/local/*` applied): clean, `checking file dlls/win32u/window.c`.
* Applying it for real in that copy reproduces the intended file byte for byte.
* The change is not compiled here (a build is in progress and the live trees must not be
  touched); `NtUserRedrawWindow`, `RDW_INVALIDATE`, `RDW_ERASE` and `RDW_UPDATENOW` are already
  used elsewhere in the same file and in `dlls/win32u/defwnd.c`.

No automated test is added to the patch. A "first `WM_PAINT` after `ShowWindow`" assertion in
`dlls/user32/tests/win.c` would pass on unpatched Wine too whenever the test's message queue
drains (the old code does deliver the queued paint then), so it would not test the defect; the
defect only shows up with a busy queue, which is exactly the non-deterministic condition the
test framework tries to avoid. The observable checks are the Hog run and
`tools/winenum/showpaint3.exe` in §6.
