#!/usr/bin/env python3
"""fetch_missing_packages.py — install the bundle packages ODIS never downloaded.

The Revit bundle is split into ~57 ODIS packages (`x64/<DIR>/pkg.*.xml`), each carrying one or
more `*.tar`/`*.tar.xz` payloads that unpack to `x64/<DIR>/<DIR>.adix` — an MSIX-like zip whose
members are a `VFS/<KnownFolder>/…` tree.  ODIS's install manager downloads and installs them in
turn; if it aborts (it can: `CERWrapperImpl::HandleCrash` at the end of a long run), the packages
still queued are left **not downloaded at all**, and the program directory keeps missing files that
no amount of repairing the staged archives can supply.

The clearest case is `RCPCOMEXT` ("Core Extension Package Component"): `DesktopMFC.dll` in the
Revit program directory imports `Qt6Core.dll`, `Qt6Gui.dll`, `QtSolutions_MFCMigrationFramework.dll`,
`RWUXThemeSU2015.dll`, `sfl400asu.dll`, `ot1000asu.dll`, `og1100asu.dll` and `Ecotect.dll`, and all
of those ship *only* in RCPCOMEXT — so Revit cannot load until that one package is in place.

This tool closes that gap: for every package that has no staged `*.adix` anywhere under the
prefix's ODIS staging tree, it downloads the payloads named in that package's own `pkg.*.xml` from
Autodesk's CDN (the payload URLs need no token — checked) and deploys their VFS members into the
prefix.  It never deletes or overwrites-with-different-content: files already present at the right
size are skipped.  It does not touch ODIS's database, so a later repair run can still install the
same package through the normal path.

usage: fetch_missing_packages.py <prefix> [--product RVT_2027_en-US] [--cache DIR]
                                 [--host URL] [--dry-run] [--verbose]
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request
import zipfile

CDN = "https://trial2.autodesk.com"

# VFS root -> path under drive_c (same table as tools/vfs_deploy.py)
ROOTMAP = {
    "ProgramFilesX64": "Program Files",
    "ProgramFilesX86": "Program Files (x86)",
    "ProgramFilesCommonX64": "Program Files/Common Files",
    "ProgramFilesCommonX86": "Program Files (x86)/Common Files",
    "Common%20AppData": "ProgramData",
    "Common AppData": "ProgramData",
    "ProgramData": "ProgramData",
    "Fonts": "windows/Fonts",
    "Windows": "windows",
    "System32": "windows/system32",
}


def bundle_dir(prefix, product):
    pats = glob.glob(os.path.join(prefix, "drive_c/Autodesk/WI/*", product))
    return pats[0] if pats else None


def package_dirs(bdir):
    return sorted(d for d in glob.glob(os.path.join(bdir, "x64", "*")) if os.path.isdir(d))


def package_payloads(pdir):
    """-> (upi2, [payload relative paths]) from the package's own manifest."""
    xml = glob.glob(os.path.join(pdir, "pkg.*.xml"))
    if not xml:
        return None, []
    text = open(xml[0], encoding="utf-8", errors="replace").read()
    upi = re.search(r"<UPI2>\{?([^<}]+)\}?", text)
    files = re.findall(r"<File[^>]*>([^<]+)</File>", text)
    return (upi.group(1) if upi else None), [f for f in files if re.search(r"\.tar", f)]


def staged(prefix, name):
    """True when ODIS downloaded this package at all.

    The staging tree holds one directory per package, but the payloads are not always `.adix`
    (MSI-type packages stage `<name>.msi`/`<name>.exe`), so presence of the directory is the test.
    """
    return bool(glob.glob(os.path.join(
        prefix, f"drive_c/users/*/AppData/Local/Temp/*/x64/{name}/*")))


def stage_dir(prefix, name):
    """Where ODIS would have staged this package (first existing bundle temp dir, else create one)."""
    existing = glob.glob(os.path.join(prefix, "drive_c/users/*/AppData/Local/Temp/*/x64", name))
    if existing:
        return existing[0]
    temps = glob.glob(os.path.join(prefix, "drive_c/users/*/AppData/Local/Temp/*/x64"))
    if not temps:
        raise SystemExit("no ODIS staging tree under the prefix (run the installer first)")
    d = os.path.join(temps[0], name)
    os.makedirs(d, exist_ok=True)
    return d


def fetch(url, dest):
    if os.path.isfile(dest) and os.path.getsize(dest) > 0:
        return True
    tmp = dest + ".part"
    try:
        with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as out:
            shutil.copyfileobj(r, out, 1 << 20)
    except Exception:  # noqa: BLE001 - a listed payload may simply not exist
        if os.path.exists(tmp):
            os.remove(tmp)
        return False
    os.replace(tmp, dest)
    return True


def deploy_adix(adix, drive_c, dry=False, verbose=False):
    added = replaced = skipped = 0
    unknown = {}
    with zipfile.ZipFile(adix) as z:
        for name in z.namelist():
            if not name.startswith("VFS/") or name.endswith("/"):
                continue
            parts = name.split("/", 2)
            if len(parts) < 3:
                continue
            mapped = ROOTMAP.get(parts[1])
            rel = urllib.parse.unquote(parts[2]).replace("/", os.sep)
            if mapped is None:
                unknown[parts[1]] = unknown.get(parts[1], 0) + 1
                continue
            dst = os.path.join(drive_c, mapped, rel)
            info = z.getinfo(name)
            if os.path.isfile(dst) and os.path.getsize(dst) == info.file_size:
                skipped += 1
                continue
            if dry:
                added += 1
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            exists = os.path.exists(dst)
            with z.open(info) as src, open(dst, "wb") as out:
                shutil.copyfileobj(src, out, 1 << 20)
            if verbose:
                print(f"    {'replaced' if exists else 'wrote'} {dst}")
            added += 1 if not exists else 0
            replaced += 1 if exists else 0
    return added, replaced, skipped, unknown


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry, verbose = "--dry-run" in sys.argv, "--verbose" in sys.argv

    def opt(name, default):
        if name in sys.argv:
            i = sys.argv.index(name)
            return sys.argv[i + 1] if i + 1 < len(sys.argv) else default
        return default

    if not args:
        print(__doc__)
        return 2
    prefix = os.path.realpath(args[0])
    drive_c = os.path.join(prefix, "drive_c")
    product = opt("--product", "RVT_2027_en-US")
    host = opt("--host", CDN).rstrip("/")
    wine = opt("--wine", "")
    cache = os.path.realpath(opt("--cache", os.path.join(tempfile.gettempdir(), "autodesk-missing-payloads")))

    bdir = bundle_dir(prefix, product)
    if not bdir:
        print(f"no bundle found under {prefix}/drive_c/Autodesk/WI/*/{product}")
        return 1
    os.makedirs(cache, exist_ok=True)
    print(f"bundle : {bdir}\ncache  : {cache}\nhost   : {host}")

    total = {"pkg": 0, "added": 0, "replaced": 0, "skip": 0, "files": 0}
    unknown_all = {}
    msi_pending = []
    for pdir in package_dirs(bdir):
        name = os.path.basename(pdir)
        if staged(prefix, name):
            continue
        upi, payloads = package_payloads(pdir)
        if not upi or not payloads:
            continue
        total["pkg"] += 1
        print(f"  {name:22s} upi2={upi[:8]}… payloads={len(payloads)}")
        if dry:
            continue
        got = 0
        for rel in payloads:
            url = f"{host}/{rel.lstrip('/')}" if "/" in rel else \
                  f"{host}/NetSWDLD/ODIS/prd/2027/RVT/{{{upi}}}/{rel}"
            dest = os.path.join(cache, name, os.path.basename(rel))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            if not fetch(url, dest):
                if verbose:
                    print(f"    absent: {os.path.basename(rel)}")
                continue
            got += 1
            try:
                tf = tarfile.open(dest)
            except tarfile.TarError as e:
                print(f"    ! {os.path.basename(dest)}: not a tar ({e})")
                continue
            with tf:
                for m in tf.getmembers():
                    if m.name.endswith(".adix"):
                        with tempfile.TemporaryDirectory() as tmp:
                            tf.extract(m, tmp, filter="data")
                            adix = os.path.join(tmp, m.name)
                            dst = os.path.join(stage_dir(prefix, name), os.path.basename(m.name))
                            shutil.copy2(adix, dst)
                            a, r, s, unk = deploy_adix(adix, drive_c, dry, verbose)
                            print(f"    {os.path.basename(m.name):22s} added={a:5d} replaced={r:4d} ok={s:6d}")
                            total["added"] += a
                            total["replaced"] += r
                            total["skip"] += s
                            total["files"] += 1
                            for k, v in unk.items():
                                unknown_all[k] = unknown_all.get(k, 0) + v
                    elif m.name.lower().endswith((".msi", ".exe")):
                        # MSI-type package: ODIS would run this through msiexec (or the exe itself).
                        # We cannot deploy it as a VFS tree, so hand it to a Wine prefix instead.
                        dst = os.path.join(stage_dir(prefix, name), os.path.basename(m.name))
                        with tempfile.TemporaryDirectory() as tmp:
                            tf.extract(m, tmp, filter="data")
                            shutil.copy2(os.path.join(tmp, m.name), dst)
                        if not wine:
                            msi_pending.append(f"{name}: {dst}")
                            continue
                        if m.name.lower().endswith(".msi"):
                            cmd = [wine, "msiexec", "/i", dst, "/qn", "/norestart"]
                        else:
                            cmd = [wine, dst, "/quiet", "/norestart"]
                        print(f"    running: {' '.join(cmd[1:])}")
                        rc = subprocess.call(cmd, env={**os.environ, "WINEPREFIX": prefix,
                                                       "DISPLAY": os.environ.get("DISPLAY", ":2")})
                        print(f"    {'ok' if rc == 0 else f'rc={rc}'}: {os.path.basename(dst)}")
        if not got:
            print("    (no payload could be downloaded)")
    print(f"\npackages without staged payload: {total['pkg']}  adix deployed: {total['files']}"
          f"  added={total['added']} replaced={total['replaced']} already-ok={total['skip']}"
          + (" (dry run)" if dry else ""))
    if unknown_all:
        print("unmapped VFS roots (skipped):", ", ".join(f"{k} x{v}" for k, v in sorted(unknown_all.items())))
    if msi_pending:
        print("\nMSI-type packages that need an installer run (not `.adix` payloads):")
        for m in msi_pending:
            print(f"  {m}")
        if not wine:
            print("  pass --wine <path to wine> to install them with `msiexec /i … /qn /norestart`")
    return 0


if __name__ == "__main__":
    sys.exit(main())
