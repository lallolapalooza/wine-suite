#!/usr/bin/env python3
"""neutralize_postinstall.py — drop the post-install actions Wine cannot run.

Two of Revit's ODIS packages declare a post-install action whose *target is a PowerShell-hosted
.NET launcher*:

| package | action | what it would do on Windows |
|---|---|---|
| `RCPCOM` ("Core Package Component", the 1.5 GB program package) | `Revit_DictionaryPermissions.exe` | run `Revit_DictionaryPermissions.ps1` to set ACLs on Revit's dictionary files |
| `RCLRVTSMPL` ("Core Content Samples") | `Revit2027_SamplesAttributes.exe` | run a script that marks the shipped sample/attribute files read-only |

With no PowerShell in the prefix the launcher exits non-zero. For `RCLRVTSMPL` that is survivable
(`<Attributes … ignoreFailure="true"/>`), but `RCPCOM` has no `ignoreFailure` — so its failure makes
the install manager roll the **whole bundle** back. The 12 `Starting UnInstallation of …` passes and
the partially deleted program directory in `Install.log` are that rollback, and it is why a "fresh"
prefix ends up with thousands of files missing.

The action list is read by `Installer.exe` from the *package manifest* under
`<prefix>/drive_c/Autodesk/WI/<bundle-guid>/RVT_2027_en-US/x64/<PKG>/pkg.<PKG>.xml`
(`<Configuration><CustomCommands><Action … type="postInstall"/>`), and the command handler takes the
program from there — so removing the `<Action>` element removes the step entirely, before any
signature check could see it. (Replacing the *executable* instead does not work: the handler
validates its Authenticode signature and our unsigned substitute is rejected —
`SignatureUtils::VerifyCertificate … -2146762496` = `TRUST_E_NOSIGNATURE`.) Everything else the
post-install phase does is left alone — e.g. `RCPCOM`'s other action,
`ODISActions.exe CreateShortcut …`, runs fine.

Files are backed up next to the original as `<name>.orig`, so `--restore` puts the manifest back
byte for byte. `--watch SECS` keeps the manifests patched for that long, which is what a fresh
install needs: the download phase writes them, the install phase reads them.

usage: neutralize_postinstall.py <prefix> [--product RVT_2027_en-US] [--only PKG[,PKG]]
                                 [--watch SECS] [--restore] [--list]
"""
import glob
import os
import re
import shutil
import sys
import time

# package -> executable file names whose postInstall action must be dropped (PowerShell-hosted)
DROP = {
    "RCLRVTSMPL": ["Revit2027_SamplesAttributes.exe"],
    "RCPCOM": ["Revit_DictionaryPermissions.exe"],
}


def manifests(prefix, product):
    return sorted(glob.glob(os.path.join(
        prefix, "drive_c/Autodesk/WI/*", product, "x64", "*", "pkg.*.xml")))


def has_powershell(prefix):
    """True only for a *working* PowerShell: Wine ships a `programs/powershell` stub (~147 kB) at the
    same path Windows uses, so a bare existence check would be wrong."""
    for rel in ("Program Files/PowerShell/7/pwsh.exe", "Program Files/PowerShell/7-preview/pwsh.exe"):
        if os.path.isfile(os.path.join(prefix, "drive_c", rel)):
            return True
    for rel in ("windows/system32/WindowsPowerShell/v1.0/powershell.exe",
                "windows/syswow64/WindowsPowerShell/v1.0/powershell.exe"):
        p = os.path.join(prefix, "drive_c", rel)
        if os.path.isfile(p) and os.path.getsize(p) > 400_000:  # Wine's stub is ~147 kB
            return True
    return False


def actions(text):
    """-> list of (action_xml, target_path, params, type) for every <Action …/> in the manifest."""
    out = []
    for m in re.finditer(r"<Action\b[^>]*/>", text):
        act = m.group(0)
        tgt = re.search(r'path="([^"]*)"', act)
        par = re.search(r'params="([^"]*)"', act)
        typ = re.search(r'type="([^"]*)"', act)
        out.append((act, tgt.group(1) if tgt else "", par.group(1) if par else "",
                    typ.group(1) if typ else ""))
    return out


def patch(path, exes, prefix, restore=False, verbose=True):
    orig = path + ".orig"
    name = os.path.basename(path)
    if restore:
        if os.path.isfile(orig):
            shutil.copy2(orig, path)
            if verbose:
                print(f"  restored {name}")
            return True
        return False
    text = open(path, encoding="utf-8", errors="replace").read()
    if "<CustomCommands>" not in text:
        return False
    ps = has_powershell(prefix)
    kept, dropped = [], []
    for act, tgt, par, typ in actions(text):
        # manifest targets are Windows paths ("%INSTALL_SOURCE%\x64\RCPCOM\Foo.exe") or bare names
        base = os.path.basename(re.sub(r"&quot;.*", "", tgt).replace("\\", "/"))
        if typ == "postInstall" and any(base.lower() == e.lower() for e in exes):
            dropped.append(f"{base} (postInstall, no PowerShell in the prefix)")
            continue
        if tgt.lower() in ("powershell", "powershell.exe") and not ps:
            dropped.append(f"{tgt} {par} ({typ})")
            continue
        kept.append(act)
    if not dropped:
        return False
    if not os.path.isfile(orig):
        shutil.copy2(path, orig)
    new = re.sub(r"(<CustomCommands>).*?(</CustomCommands>)",
                 lambda m: m.group(1) + "".join(kept) + m.group(2), text, count=1, flags=re.S)
    open(path, "w", encoding="utf-8").write(new)
    if verbose:
        for d in dropped:
            print(f"  dropped {name}: {d}")
    return True


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]

    def opt(name, default=None):
        if name in sys.argv:
            i = sys.argv.index(name)
            return sys.argv[i + 1] if i + 1 < len(sys.argv) else default
        return default

    if not args:
        print(__doc__)
        return 2
    prefix = os.path.realpath(args[0])
    product = opt("--product", "RVT_2027_en-US")
    only = [p.strip() for p in (opt("--only", "") or "").split(",") if p.strip()]
    watch = float(opt("--watch", 0) or 0)
    restore = "--restore" in sys.argv

    if "--list" in sys.argv:
        for man in manifests(prefix, product):
            for act, tgt, par, typ in actions(open(man, encoding="utf-8", errors="replace").read()):
                print(f"  {os.path.basename(os.path.dirname(man)):22s} {typ:14s} {tgt} {par[:60]}")
        return 0

    deadline = time.time() + watch if watch else 0
    first = True
    while True:
        for man in manifests(prefix, product):
            pkg = os.path.basename(os.path.dirname(man))
            if pkg not in DROP or (only and pkg not in only):
                continue
            patch(man, DROP[pkg], prefix, restore=restore, verbose=watch == 0)
        if not watch:
            break
        if first:
            print(f"watching {prefix} for {watch:.0f}s (patching package manifests as they appear)")
            first = False
        if deadline and time.time() > deadline:
            break
        time.sleep(2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
