#!/usr/bin/env python3
"""Run Notepad++ under Wine and report whether dark mode is actually applied.

Checks the menu bar (the bug), the toolbar and the editor background.
Menu bar light on white while the rest is dark == bug 57555 reproduced.
"""
import argparse
import os
import re
import subprocess
import sys
import time

from PIL import Image

WD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREFIX = os.path.join(WD, "prefix")
NPP_CFG = os.path.join(PREFIX, "drive_c/NPP/config.xml")
DISPLAY = ":99"
LIGHTISH = 200  # channel value above which a pixel counts as "light"


def start_xvfb():
    if not os.path.exists("/tmp/.X11-unix/X99"):
        subprocess.Popen(["Xvfb", DISPLAY, "-screen", "0", "1600x1000x24", "-nolisten", "tcp"],
                         stdout=open(os.path.join(WD, "xvfb.log"), "wb"),
                         stderr=subprocess.STDOUT, start_new_session=True)
        for _ in range(100):
            if os.path.exists("/tmp/.X11-unix/X99"):
                break
            time.sleep(0.1)
    return os.path.exists("/tmp/.X11-unix/X99")


def set_config(mode="dark"):
    """mode: dark | light | follow-windows"""
    cfg_path = os.path.join(PREFIX, "drive_c/NPP/config.xml")
    cfg = open(cfg_path).read()
    enable = "yes" if mode == "dark" else "no"
    winmode = "yes" if mode == "follow-windows" else "no"
    cfg = re.sub(r'(<GUIConfig name="DarkMode" enable=")\w+(")', r"\g<1>%s\g<2>" % enable, cfg)
    cfg = re.sub(r'(<GUIConfig name="DarkMode"[^>]*enableWindowsMode=")\w+(")',
                 r"\g<1>%s\g<2>" % winmode, cfg)
    open(cfg_path, "w").write(cfg)
    m = re.search(r'<GUIConfig name="DarkMode"[^>]*>', cfg)
    print("  config:", "enable=" + re.search(r'enable="(\w+)"', m.group(0)).group(1),
          "enableWindowsMode=" + re.search(r'enableWindowsMode="(\w+)"', m.group(0)).group(1))


def kill_prefix_wineserver():
    """shut down every process (incl. the wineserver) using our WINEPREFIX.

    SIGTERM first: the wineserver flushes the registry to disk on a clean exit,
    a SIGKILL would lose recent reg writes."""
    import glob
    target = PREFIX.encode()
    pids = []
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            data = open(proc + "/environ", "rb").read()
        except OSError:
            continue
        if any(e.startswith(b"WINEPREFIX=") and target in e for e in data.split(b"\0")):
            pids.append(int(proc.rsplit("/", 1)[1]))
    for sig in (15, 9):
        remaining = []
        for pid in pids:
            try:
                os.kill(pid, sig)
                remaining.append(pid)
            except OSError:
                pass
        if not remaining:
            break
        time.sleep(2)
        pids = remaining
    time.sleep(1)


def kill_npp(env):
    subprocess.run(["pkill", "-9", "-f", "notepad++.exe"], env=env)
    kill_prefix_wineserver()
    time.sleep(1)


def run(wine, dllpath, tag, wait=14):
    env = dict(os.environ, DISPLAY=DISPLAY, WINEPREFIX=PREFIX, WINEDEBUG="-all")
    if dllpath:
        env["WINEDLLPATH"] = dllpath
    kill_npp(env)

    cmd = [wine, "C:\\NPP\\notepad++.exe"]
    proc = subprocess.Popen(cmd, env=env, stdout=open(os.path.join(WD, "npp_%s.log" % tag), "wb"),
                            stderr=subprocess.STDOUT, start_new_session=True)
    wid = ""
    for _ in range(wait * 2):
        out = subprocess.run(["xdotool", "search", "--name", "Notepad++"], env=env,
                             capture_output=True, text=True).stdout.split()
        if out:
            wid = out[-1]
            break
        time.sleep(0.5)
    if not wid:
        print("  ERROR: no Notepad++ window appeared")
        return None
    time.sleep(4)
    # park the pointer so hovering does not highlight menu items
    subprocess.run(["xdotool", "mousemove", "1500", "980"], env=env)
    time.sleep(0.5)
    geo = subprocess.run(["xdotool", "getwindowgeometry", wid], env=env,
                         capture_output=True, text=True).stdout
    m = re.search(r"Position: (\d+),(\d+).*?Geometry: (\d+)x(\d+)", geo, re.S)
    x, y, w, h = (int(g) for g in m.groups())
    shot = os.path.join(WD, "shot_%s.png" % tag)
    subprocess.run(["import", "-window", "root", shot], env=env)
    im = Image.open(shot).convert("RGB")

    def band(dy0, dy1, fx):
        """median colour over a band, sampling blank areas only"""
        px = [im.getpixel((x + int(w * f), y + dy))
              for dy in range(dy0, dy1 + 1) for f in fx]
        px.sort(key=lambda p: sum(p))
        return px[len(px) // 2]

    blank = (0.60, 0.70, 0.80, 0.90)
    res = {"geom": (x, y, w, h), "shot": shot,
           "menu": band(6, 20, blank), "toolbar": band(30, 42, blank),
           "editor": im.getpixel((x + w // 2, y + 130))}
    return res, env


def verdict(res):
    def dark(px):
        return max(px) < 130

    print("  menu bar (median):", res["menu"])
    print("  toolbar  (median):", res["toolbar"])
    print("  editor            :", res["editor"])
    menu_dark, bar_dark = dark(res["menu"]), dark(res["toolbar"])
    if bar_dark and not menu_dark:
        return "BUG (chrome dark, menu bar light)"
    if bar_dark and menu_dark:
        return "OK (dark mode fully applied)"
    if not bar_dark and not menu_dark:
        return "LIGHT MODE"
    return "UNEXPECTED"


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--wine", required=True)
    ap.add_argument("--dllpath", default="")
    ap.add_argument("--mode", default="dark", choices=["dark", "light", "follow-windows"])
    ap.add_argument("--tag", default="test")
    ap.add_argument("--prefix", default=PREFIX)
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()

    PREFIX = a.prefix

    start_xvfb()
    print("mode:", a.mode)
    set_config(a.mode)
    r = run(a.wine, a.dllpath, a.tag)
    if r:
        res, env = r
        print("verdict:", verdict(res))
        if not a.keep:
            kill_npp(env)
