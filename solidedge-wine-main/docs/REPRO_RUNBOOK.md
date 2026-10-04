# Runbook: reproduce and diagnose the three defects, once a 3D licence is available

Everything below is built and exercised; the only missing input is a licence that enables the
**Part / Sketch** environment (see FINDINGS M13 for why the installer's own activation code no
longer yields one).  Nothing here needs new code.

## 0. Start the pieces

```sh
# VNC display (already running in this session): 1600x1000 on port 5902
Xtigervnc :2 -geometry 1600x1000 -depth 24 -rfbport 5902 -SecurityTypes None -AlwaysShared -desktop solidedge &

# Solid Edge, on that display, in the prefix that has it installed
tools/se_launch.sh run1 --prefix state/work/prefix --softgl -- 'C:\t.par'
#   --softgl sets LIBGL_ALWAYS_SOFTWARE=1: required on :2, where hardware GL + swap interval 1
#   blocks ~900 ms per present (FINDINGS M10, measured with a *native* X client too).
```

`tools/se_launch.sh <tag>` leaves stderr at `logs/runs/<tag>/se.stderr` and prints the window list.
Add `--debug '+timestamp,+dwmapi'` to get a Wine log whose lines carry elapsed time (FINDINGS M8).

## 1. Bug 2 — "Close Sketch" does nothing

1. In the Part environment, start a Sketch, then click **Close Sketch** in the Sketch tab.
2. Watch the terminal for `fixme:dwmapi:` — with `patches/local/0023` there must be **none**
   (before it: `fixme:dwmapi:DwmGetWindowAttribute attribute 14 not implemented.`).  If the line
   is gone and the sketch still will not close, the DWM answer was not the cause and the next
   step finds what is.
3. Script the click and align it with the log:

   ```sh
   W=$(tools/host/ui.sh :2 find '"Solid Edge 2D Drafting')
   tools/se_drive.sh "$W" tools/actions/close_sketch.txt --display :2     # click + note markers
   ```

   Every `drive.log` line is millisecond-stamped, and `WINEDEBUG=+timestamp,…` stamps the Wine
   side with elapsed time from the same host clock, so "the last call before it stopped" is read
   straight off the two files.
4. If the log stops inside a DLL, name the caller of the suspect import with
   `tools/xref.py <dll> <Import>` (FINDINGS M8), then disassemble around that VA — that is how
   `control.dll`'s `SC_CLOSE` sites were found.
5. The managed half is already traced: `UIAutomationClient.IsWindowReallyVisible` →
   `IsWindowCloaked` → `DwmGetWindowAttribute(hwnd, 14, …)`, reached from
   `HwndProxyElementProvider.GetNextSibling/…`.  `tools/winapi/uiaprobe.cs` reproduces exactly that
   managed walk (it is the probe that found the second gap, `patches/local/0024`).

## 2. Bug 3 — the title-bar X is greyed

1. Screenshot the caption and judge it: `tools/host/ui.sh :2 shot <win> /tmp/x.png` and crop the
   top-right 150x40 — the same crop used to show the X enabled in the reachable modes
   (`logs/drive/titlebar_zoom.png`).
2. Click it and count processes: `xdotool mousemove 1586 20 click 1; pgrep -c -f Edge.exe`.
   In the reachable modes this **closes Solid Edge cleanly** (measured), so bug 3 is not present
   there — consistent with it being a *consequence* of bug 2: while a command is stuck, the frame
   keeps Close disabled.
3. To see who disables it, capture `WINEDEBUG=+menu` and look for `EnableMenuItem` on `SC_CLOSE`
   (0xf060) while the command is active.

## 3. Bug 1 — the viewport flickers black

Measure, do not look:

```sh
python3 tools/host/flicker.py <tag> --display :2 --secs 20 --interval 0.25 \
        --region <x,y,w,h of the viewport>            # prints black_fraction
python3 tools/host/winwatch.py --display :2 --secs 20 --interval 0.2 --filter 'Drafting|Solid Edge'
```

* `flicker.py` verdicts every frame `BLACK / DARK / CONTENT` from the region's histogram and keeps
  only the failing frames; `black_fraction` is the number to move.  In the modes reachable here it
  measured **0.000** at idle, while zooming, while rotating and after the Wine rebuild.
* `winwatch.py` reports windows being created/destroyed/moved — a viewport that flickers because
  its window is re-created every frame looks completely different from one that is repainted
  underneath something, and the two need different fixes.
* Then capture the GL traffic: `tools/run_se.sh <tag> --debug '+timestamp,+wgl'` (or a temporary
  `WARN` in `dlls/win32u/opengl.c`) around `wglSwapBuffers` / `opengl_drawable_flush`, and compare
  against the same interaction with `wglSwapIntervalEXT(0)` forced by the application's own
  graphics setting — a display whose present blocks shows up as a ~1 s period, a compositing
  problem does not.

## 4. Windows reference (differential method)

The guest is usable for **window state and API contracts**, not for graphics: it has no GPU
driver, so its OpenGL is `GDI Generic` 1.1 with every pixel format `GENERIC_FORMAT` (M7).

```sh
# guest command channel (one agent at a time)
tools/vm/vmcmd.sh '"alive=" + (Get-Date -Format o)'
tools/vm/vmcmd.sh -f tools/vm/install_se_guest.ps1 3600      # mirror media + install, if disk allows
tools/vm/gshot.sh state/vm/now.png                            # guest screen
```

Probes already written to run on both sides and be diffed:
`tools/winapi/dwmprobe.c` (DwmGetWindowAttribute contract), `tools/winapi/wglprobe.c`
(pixel formats, WGL extensions, renderer), `tools/winapi/swapprobe.c` (SwapBuffers timing),
`tools/winapi/glchild.c` (viewport-shaped GL child), `tools/winapi/uiaprobe.cs` (.NET UIA walk).
Build the C ones with `x86_64-w64-mingw32-gcc`; `uiaprobe.cs` is compiled **inside** the prefix with
the .NET Framework's own `csc.exe` (see the header comment in the file).
