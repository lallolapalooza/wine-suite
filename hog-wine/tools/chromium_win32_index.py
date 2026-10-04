#!/usr/bin/env python3
"""Index the Win32 surface of Chromium 80.0.3987.163 (QtWebEngine's Chromium).

Chromium is far too large to clone, so individual files are fetched at the exact
tag from chromium.googlesource.com and cached under --cache:

    https://chromium.googlesource.com/chromium/src/+/<TAG>/<path>?format=TEXT
    (the response body is base64 of the file contents)

Directory listings come from the plain HTML view of a directory, whose entries
appear as `>name.cc</a>`.

The same Wine .spec cross-check used for Qt is applied, so the output tells you
whether Wine implements / stubs / lacks each API Chromium calls.
"""

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qt_win32_index as qidx  # noqa: E402

TAG = "80.0.3987.163"
BASE = "https://chromium.googlesource.com/chromium/src/+/" + TAG

# Whole directories worth of sources (small, dense in Win32 calls).
FULL_DIRS = ["base/win/", "sandbox/win/src/", "ui/gfx/win/"]
# Directories where only files matching the regex are interesting.
PATTERN_DIRS = {
    "gpu/ipc/service/": r"(win|d3d|direct_composition|gpu_init|gpu_channel_manager|gpu_watchdog|gpu_main)",
    "gpu/config/": r"(win|gpu_info_collector|gpu_util|gpu_feature_info)",
    "ui/gl/": r"(win|egl|wgl|gl_factory|gl_initializer|gl_surface|gl_util|gl_bindings)",
    "ui/gl/init/": r".*",
    "content/gpu/": r".*",
    "content/app/": r"(content_main_runner|sandbox)",
    "net/base/": r"(network_change_notifier_win|network_interfaces_win)",
    "net/proxy_resolution/": r"winhttp",
    "base/process/": r"win",
    "base/files/": r"win",
    "base/threading/": r"win",
    "base/time/": r"win",
    "base/debug/": r"win",
    "base/synchronization/": r"win",
    "base/memory/": r"win",
    "crypto/": r"(random|ec_|rsa_|secure_util)",
    "device/gamepad/": r"(win|xinput)",
    "media/gpu/": r"(win|dxva)",
}
EXTRA_FILES = [
    "ui/gl/init/gl_initializer_win.cc",
    "ui/gl/init/gl_factory_win.cc",
    "ui/gl/gl_surface_wgl.cc",
    "ui/gfx/win/direct_write.cc",
    "base/win/windows_version.cc",
    "sandbox/win/src/process_mitigations.cc",
    "net/base/network_change_notifier_win.cc",
]


def fetch(path, cache, retries=3):
    """Fetch one file (base64 -> bytes) into cache. Returns local path or None."""
    dest = os.path.join(cache, path)
    if os.path.isfile(dest) and os.path.getsize(dest) > 0:
        return dest
    url = "%s/%s?format=TEXT" % (BASE, path)
    raw = _get(url)
    if raw is None:
        return None
    try:
        data = base64.b64decode(raw)
    except Exception:
        return None
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as fh:
        fh.write(data)
    return dest


ENTRY = re.compile(r'>([A-Za-z0-9_.\-]+\.(?:cc|h|mm|gn))</a>')


def _get(url, retries=6):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            # googlesource throttles aggressively (429/503): back off hard
            time.sleep(2.0 * (attempt + 1) ** 2)
        except Exception:
            time.sleep(2.0 * (attempt + 1) ** 2)
    return None


def list_dir(d, cache):
    d = d.strip("/")
    # NOTE: the trailing slash triggers 429s; the bare path 200s.
    url = "%s/%s" % (BASE, d)
    html = _get(url)
    if html is None:
        print("  ! listing failed %s" % d)
        return []
    text = html.decode("utf-8", "replace")
    names = sorted(set(ENTRY.findall(text)))
    return [d + "/" + n for n in names]


def collect_paths():
    paths = []
    for d in FULL_DIRS:
        paths += list_dir(d, None)
    for d, pat in PATTERN_DIRS.items():
        rx = re.compile(pat)
        for p in list_dir(d, None):
            if rx.search(os.path.basename(p)):
                paths.append(p)
    paths += EXTRA_FILES
    return sorted(set(paths))


def scan_files(files, names, base):
    hits = {}
    lookup = qidx.build_lookup(names)
    for path in files:
        rel = os.path.relpath(path, base)
        if "_unittest" in rel or rel.endswith("_test.cc") or "/tests/" in rel:
            continue
        state = {"block": False}
        try:
            with open(path, "r", errors="replace") as fh:
                for lineno, raw in enumerate(fh, 1):
                    code = qidx.strip_comment(raw, state)
                    if not code.strip():
                        continue
                    for m in qidx.TOKEN.finditer(code):
                        tok = m.group(0)
                        api = lookup.get(tok)
                        if api and qidx._is_hit(code, m, tok):
                            hits.setdefault(api, []).append({
                                "file": rel, "line": lineno,
                                "text": raw.strip(), "token": tok})
        except OSError:
            pass
    return hits


def main():
    global TAG, BASE
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default="/run/media/asdf/Windows/chromium-src")
    ap.add_argument("--wine-root", default="/home/asdf/projects/hog-wine/wine-11.18")
    ap.add_argument("--winapi-root",
                    default="/run/media/asdf/Windows/qt-src/winapi/winapi-0.3.9")
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-md", default="")
    ap.add_argument("--tag", default=TAG)
    ap.add_argument("--paths-file", default="",
                    help="explicit list of repo-relative files (skips directory listing)")
    args = ap.parse_args()
    TAG, BASE = args.tag, "https://chromium.googlesource.com/chromium/src/+/" + args.tag

    os.makedirs(args.cache, exist_ok=True)
    if args.paths_file:
        with open(args.paths_file) as fh:
            paths = [l.strip() for l in fh if l.strip()]
        print("paths from %s: %d" % (args.paths_file, len(paths)))
    else:
        print("listing directories at %s ..." % TAG)
        paths = collect_paths()
    print("files selected: %d" % len(paths))
    ok = []
    with ThreadPoolExecutor(max_workers=5) as ex:
        for p, local in zip(paths, ex.map(lambda x: fetch(x, args.cache), paths)):
            if local:
                ok.append(local)
    print("files fetched: %d" % len(ok))

    specs = qidx.load_wine_specs(args.wine_root)
    winapi = qidx.load_winapi(args.winapi_root)
    named_specs = {n for n, es in specs.items()
                   if any(not e.get("noname") for e in es)}
    names = (named_specs | set(winapi) | set(qidx.EXPECT)) - qidx.DENY
    hits = scan_files(ok, names, args.cache)
    print("apis referenced by Chromium: %d" % len(hits))

    rank = {d: i for i, d in enumerate(qidx.DLL_PREFERENCE)}

    def pick(entries):
        return sorted(entries, key=lambda e: (rank.get(e["dll"], 999),
                                              e["kind"] == "ordinal"))[0]

    result = {}
    for api in sorted(hits):
        w = specs.get(api)
        if w:
            primary = pick(w)
            status, dll = primary["kind"], primary["dll"]
            dlls = sorted({e["dll"] for e in w}, key=lambda d: rank.get(d, 999))
            if status == "stub" and any(e["kind"] != "stub" for e in w):
                status = "forward" if any(e["kind"] == "forward" for e in w) else "impl"
        else:
            primary, status, dll, dlls = {}, "absent", "", []
            mods = winapi.get(api, set())
            dlls = sorted({qidx.MODULE_DLL.get(m, m) for m in mods})
        if status in ("absent", "stub") and api in qidx.NOT_WINE:
            status = "not-an-export"
        result[api] = {
            "wine_dll": dll, "wine_dlls": dlls, "wine_status": status,
            "wine_spec": primary.get("file", ""),
            "wine_spec_line": primary.get("line", 0),
            "wine_raw": primary.get("raw", ""),
            "sites": hits[api],
        }

    if args.out_json:
        with open(args.out_json, "w") as fh:
            json.dump(result, fh, indent=1, sort_keys=True)
    if args.out_md:
        with open(args.out_md, "w") as fh:
            fh.write("| Win32 API | Wine DLL | Status | Chromium %s | What Chromium does |\n" % TAG)
            fh.write("|---|---|---|---|---|\n")
            for api in sorted(result):
                d = result[api]
                s = d["sites"][0]
                st = d["wine_status"]
                if st == "absent":
                    st = "**absent**"
                elif st == "stub":
                    st = "**stub**"
                exp = qidx.EXPECT.get(api, "")
                if not exp:
                    exp = "`" + s["text"].replace("|", "\\|") + "`"
                fh.write("| `%s` | %s | %s | %s:%d | %s |\n" %
                         (api, d["wine_dll"] or ",".join(d["wine_dlls"]), st,
                          s["file"], s["line"], exp.replace("|", "\\|")))

    from collections import Counter
    print("status counts:", dict(Counter(d["wine_status"] for d in result.values())))
    print("flagged:")
    for api in sorted(result):
        if result[api]["wine_status"] in ("stub", "absent"):
            d = result[api]
            print("  %-32s %-8s %-12s %s" % (api, d["wine_status"], d["wine_dll"],
                                             d["sites"][0]["file"] + ":" + str(d["sites"][0]["line"])))


if __name__ == "__main__":
    sys.exit(main())
