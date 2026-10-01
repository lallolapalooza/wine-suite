#!/bin/bash
# =============================================================================
# tools/check_prereqs.sh — what this machine still needs to build the patched Wine
# and install/run AutoCAD 2027 with it.
#
# usage: tools/check_prereqs.sh [--media DIR] [--prefix PATH] [--quiet]
#
#   --media DIR    Autodesk ODIS media (Setup.exe + ODIS/); default $ACAD/installer
#   --prefix PATH  also report on an installed prefix (default: none)
#   --quiet        only the summary and the next steps
#
# exit: 0 = nothing blocking (optional gaps may still be listed), 1 = a hard requirement is missing
#
# Nothing here modifies the machine.  Every [MISSING] line names the package or the step
# that fixes it; the closing list is the ordered "what to do next" for this machine.
# =============================================================================
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh" 2>/dev/null || true

MEDIA=${ACAD_MEDIA:-$ROOT/installer}
PREFIX_IN=""
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --media)  MEDIA="$2"; shift 2 ;;
    --prefix) PREFIX_IN="$2"; shift 2 ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

HARDFAIL=0
HARD_PKGS=(); SOFT_PKGS=(); STEPS=(); OPTNOTES=()

section() { [ "$QUIET" = 1 ] || printf '\n== %s\n' "$*"; }
ok()      { [ "$QUIET" = 1 ] || printf '  [ ok ]      %s\n' "$*"; }
note()    { [ "$QUIET" = 1 ] || printf '  [note]      %s\n' "$*"; }
opt()     { [ "$QUIET" = 1 ] || printf '  [ opt]      %s\n' "$*"; }
warn()    { printf '  [warn]      %s\n' "$*"; }
missing() { printf '  [MISSING]   %s\n' "$*"; }
hard()    { HARDFAIL=1; missing "$1"; [ -n "${2:-}" ] && HARD_PKGS+=("$2"); }
step()    { STEPS+=("$1"); }
have()    { command -v "$1" >/dev/null 2>&1; }

# <binary> <apt package> [soft]
need_cmd() {
  local bin=$1 pkg=${2:-} kind=${3:-hard}
  if have "$bin"; then ok "$bin -> $(command -v "$bin")"
  elif [ "$kind" = soft ]; then opt "$bin not installed (package: $pkg)"
  else hard "$bin not installed (apt package: $pkg)" "$pkg"; fi
}

# <pkg-config module> <apt package> [soft]
need_pc() {
  local m=$1 pkg=${2:-} kind=${3:-hard}
  if pkg-config --exists "$m" 2>/dev/null; then ok "pkg-config $m $(pkg-config --modversion "$m" 2>/dev/null)"
  elif [ "$kind" = soft ]; then opt "pkg-config $m not present (package: $pkg) — feature will be compiled out"
  else hard "pkg-config $m not present (apt package: $pkg)" "$pkg"; fi
}

# >= comparison for "x.y.z" version strings
ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

printf 'checkout: %s\nmedia   : %s\n' "$ROOT" "$MEDIA"

# ------------------------------------------------------- 1. the checkout -----
section "1. checkout contents"
if [ -d "$ROOT/wine-11.18" ] && [ -f "$ROOT/wine-11.18/configure" ]; then
  ok "wine-11.18/ Wine source tree"
else
  hard "wine-11.18/ missing (the patched Wine source tree)" ""
fi

if [ -d "$ROOT/patches" ]; then
  total=0; applied=0; notapplied=()
  if have patch; then
    for p in "$ROOT"/patches/*.patch; do
      [ -f "$p" ] || continue
      total=$((total + 1))
      if ( cd "$ROOT/wine-11.18" && patch -p1 -R --dry-run -i "$p" >/dev/null 2>&1 ); then
        applied=$((applied + 1))
      else
        notapplied+=("$(basename "$p")")
      fi
    done
    if [ "$applied" = "$total" ] && [ "$total" -gt 0 ]; then
      ok "all $total patches are applied to wine-11.18/"
    elif [ "$applied" = 0 ]; then
      warn "wine-11.18/ looks unpatched (none of the $total patches apply in reverse)"
      step "apply the patch series to wine-11.18/ (it is shipped already applied, so this is unexpected)"
    else
      hard "$((total - applied)) of $total patches are NOT applied: ${notapplied[*]}" ""
    fi
  else
    hard "'patch' not installed (apt package: patch)" "patch"
  fi
else
  hard "patches/ missing" ""
fi

for s in run_build.sh ui_plug.sh tools/install_fresh_prefix.sh tools/verify_fresh_prefix.sh \
         tools/make_wine_fonts.py tools/fix_licensing_registration.sh; do
  [ -f "$ROOT/$s" ] && ok "$s" || hard "$s missing" ""
done

# --------------------------------------------------------- 2. toolchain -----
section "2. build toolchain (configure hard-fails without these)"
need_cmd make make
need_cmd m4 m4
need_cmd patch patch
need_cmd pkg-config pkg-config
need_cmd python3 python3

if have flex; then
  v=$(flex --version 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*' | head -1)
  if [ -n "$v" ] && ge "$v" 2.5.33; then ok "flex $v (needs >= 2.5.33)"; else hard "flex too old or unreadable: ${v:-unknown} (needs >= 2.5.33)" flex; fi
else hard "flex not installed (needs >= 2.5.33)" flex; fi

if have bison; then
  v=$(bison --version 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*' | head -1)
  if [ -n "$v" ] && ge "$v" 3.0; then ok "bison $v (needs >= 3.0)"; else hard "bison too old or unreadable: ${v:-unknown} (needs >= 3.0)" bison; fi
else hard "bison not installed (needs >= 3.0)" bison; fi

# The C compiler that builds the Unix side, and the PE cross compiler for the Windows
# side.  Wine accepts mingw-w64 or clang+lld+(llvm-)dlltool; the reference
# configuration used clang:  ./configure --enable-archs=i386,x86_64
if have clang; then ok "clang $(clang --version 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*' | head -1) (unix side + PE with lld)"
elif have gcc; then ok "gcc $(gcc -dumpversion 2>/dev/null) (unix side)"
else hard "no C compiler (clang / gcc)" clang; fi

if have x86_64-w64-mingw32-gcc; then
  ok "x86_64-w64-mingw32-gcc (mingw-w64 PE cross compiler)"
elif have clang && have lld; then
  ok "clang + lld (PE cross compiler)"
  have llvm-dlltool || need_cmd llvm-dlltool llvm
elif have clang; then
  hard "clang without lld: the PE build needs the LLVM linker (apt package: lld)" lld
else
  hard "no PE cross compiler: install mingw-w64 or clang+lld" mingw-w64
fi

# --------------------------------------------------- 3. build libraries -----
section "3. libraries configure looks for"
# freetype is what renders every font acad's UI uses; without it the UI is blank even
# though the font files are in the prefix.
need_pc freetype2 libfreetype-dev
# winex11: without these the Windows are drawn, but slower / without the X extensions.
for m in x11:libx11-dev xext:libxext-dev xrender:libxrender-dev xrandr:libxrandr-dev \
         xi:libxi-dev xcursor:libxcursor-dev xinerama:libxinerama-dev xfixes:libxfixes-dev \
         xcomposite:libxcomposite-dev xkbcommon:libxkbcommon-dev; do
  need_pc "${m%%:*}" "${m##*:}" soft
done
# TLS for the licensing/WebView2 HTTPS traffic
need_pc gnutls libgnutls28-dev soft
# Everything else Wine can compile out.  The reference build ran AutoCAD with
# Xrender/Xcursor/Xi/Shm/Vulkan/SDL2/pulse/alsa/dbus/udev/fontconfig absent, so none of
# these is a requirement - install them only for the extra features listed.
for m in fontconfig:libfontconfig-dev dbus-1:libdbus-1-dev alsa:libasound2-dev \
         pulse:libpulse-dev vulkan:libvulkan-dev wayland-client:libwayland-dev \
         libunwind:libunwind-dev cups:libcups2-dev libudev:libudev-dev \
         gstreamer-1.0:libgstreamer1.0-dev krb5:libkrb5-dev ldap:libldap2-dev \
         libxml-2.0:libxml2-dev ncurses:libncurses-dev zlib:zlib1g-dev; do
  need_pc "${m%%:*}" "${m##*:}" soft
done

# ------------------------------------------------------ 4. wine build -------
section "4. patched Wine build"
WINE_BUILD=$ROOT/wine-install/bin/wine
if [ -x "$WINE_BUILD" ]; then
  ok "wine-install/bin/wine ($("$WINE_BUILD" --version 2>/dev/null))"
  if [ -f "$ROOT/wine-install/share/wine/fonts/tahoma.ttf" ]; then
    ok "wine-install/share/wine/fonts/tahoma.ttf (source for micross.ttf)"
  else
    warn "wine-install/share/wine/fonts/tahoma.ttf absent: tools/make_wine_fonts.py cannot build micross.ttf"
    step "re-run tools/build_wine.sh (its 'make install' stage installs Wine's fonts)"
  fi
else
  missing "wine-install/bin/wine is not built yet"
  step "build it: tools/build_wine.sh   (copies wine-11.18 -> wine/, configures, makes, installs into wine-install/)"
fi
if [ -d "$ROOT/wine/wine-11.18" ]; then
  [ -f "$ROOT/wine/wine-11.18/Makefile" ] && ok "wine/wine-11.18 configured" || note "wine/wine-11.18 exists but is not configured yet"
else
  note "no build tree yet (tools/build_wine.sh creates wine/wine-11.18 from wine-11.18/)"
fi

# --------------------------------------------------- 5. python + venv -------
section "5. python for the install/verify scripts"
if python3 -c 'import sqlite3' 2>/dev/null; then ok "python3 sqlite3 module"; else hard "python3 sqlite3 module missing (apt package: python3)" python3; fi
VENV=$ROOT/tools/venv/bin/python
if [ -x "$VENV" ]; then
  ok "tools/venv"
  if "$VENV" -c 'import fontTools' 2>/dev/null; then
    ok "fonttools in tools/venv (tools/make_wine_fonts.py)"
  else
    hard "fonttools missing from tools/venv — the font fixup cannot run" ""
    step "tools/venv/bin/pip install fonttools    (or: pip install fonttools)"
  fi
else
  hard "tools/venv missing — install_fresh_prefix.sh and verify_fresh_prefix.sh call tools/venv/bin/python" ""
  step "python3 -m venv tools/venv && tools/venv/bin/pip install fonttools"
fi

# ------------------------------------------------------- 6. UI runs --------
section "6. X display + tools for the UI runs (ui_plug.sh / verify_fresh_prefix.sh)"
DISPX=${DISP:-:2}
need_cmd xwininfo x11-utils
need_cmd xdotool  xdotool
need_cmd import   imagemagick
need_cmd pgrep    procps
if have xdpyinfo && xdpyinfo -display "$DISPX" >/dev/null 2>&1; then
  ok "X display $DISPX reachable"
else
  hard "no X display on $DISPX (the scripts default to it; DISP=... overrides)" ""
  step "start one:  Xvfb $DISPX -screen 0 1920x1080x24 &   (or Xtigervnc $DISPX -geometry 1920x1080 -SecurityTypes None -localhost & to watch it)"
fi

# --------------------------------------------------------- 7. fonts --------
section "7. host fonts the prefix font fixup builds from"
LIB=/usr/share/fonts/truetype/liberation
for f in LiberationSans-Regular.ttf LiberationSans-Bold.ttf; do
  if [ -f "$LIB/$f" ] || [ -f "/usr/share/fonts/liberation/$f" ]; then ok "$f"; else
    hard "$f missing (arial.ttf/arialbd.ttf are built from it)" fonts-liberation
  fi
done
[ -f "$ROOT/wine-install/share/wine/fonts/tahoma.ttf" ] && ok "tahoma.ttf (source for micross.ttf)" \
  || note "tahoma.ttf comes with the Wine build (see 4.)"

# --------------------------------------------------------- 8. media -------
section "8. Autodesk install media (your own download; not redistributed)"
if [ -f "$MEDIA/Setup.exe" ] && [ -d "$MEDIA/ODIS" ]; then
  ok "ODIS media at $MEDIA (Setup.exe + ODIS/)"
elif [ -f "$MEDIA/Setup.exe" ]; then
  hard "$MEDIA has Setup.exe but no ODIS/ directory (incomplete extraction)" ""
else
  hard "no ODIS media at $MEDIA" ""
  step "extract your AutoCAD 2027 download so that $MEDIA/Setup.exe and $MEDIA/ODIS/ exist (see SETUP.md)"
fi
[ "$MEDIA" = "$ROOT/installer" ] || note "media taken from --media/ACAD_MEDIA=$MEDIA (default would be $ROOT/installer)"

if [ -f "$ROOT/pkgs/x/x64/acadprivate/acadprivate.msi" ]; then
  ok "pkgs/ acadprivate payload present (--repair path)"
else
  opt "pkgs/ absent — only needed by tools/install_fresh_prefix.sh --repair (a normal install fetches its packages itself)"
fi
if [ -f "$ROOT/pkgs/dotnet/dotnet.exe" ] || [ -f "$ROOT/pkgs/dotnet/dotnet" ]; then
  ok "pkgs/dotnet (offline .NET Desktop Runtime)"
else
  opt "no pkgs/dotnet — the .NET Desktop Runtime is downloaded from builds.dotnet.microsoft.com if needed"
fi
FIXTURE=${VERIFY_DWG:-$ROOT/tools/refdata/verify/titleblock.dwg}
[ -f "$FIXTURE" ] && ok "drawing fixture $FIXTURE" \
  || opt "no drawing fixture ($FIXTURE): verify runs without a drawing, or set VERIFY_DWG=<your .dwg>"

if have curl && curl -fsS -o /dev/null -m 8 https://dl.winehq.org/ 2>/dev/null; then
  ok "network reachable (the unattended install downloads its packages from Autodesk)"
else
  warn "no network (or no curl): tools/install_fresh_prefix.sh downloads the AutoCAD packages during Setup.exe -q"
fi

# ------------------------------------------------------ 9. resources -------
section "9. resources"
avail_kb=$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "${avail_kb:-}" ]; then
  avail_gb=$((avail_kb / 1024 / 1024))
  if   [ "$avail_gb" -ge 40 ]; then ok "${avail_gb} GB free on $ROOT"
  elif [ "$avail_gb" -ge 20 ]; then warn "${avail_gb} GB free on $ROOT — the build tree, the media and an installed prefix want ~40 GB"
  else hard "${avail_gb} GB free on $ROOT — not enough for a build plus an installed prefix (~40 GB)" ""; fi
fi
[ "$QUIET" = 1 ] || printf '  [note]      %s cores, %s GB RAM\n' "$(nproc)" "$(awk '/MemTotal/{printf "%.0f", $2/1048576}' /proc/meminfo)"

# ---------------------------------------------------- 10. the prefix -------
if [ -n "$PREFIX_IN" ]; then
  section "10. prefix $PREFIX_IN"
  P=$(readlink -f "$PREFIX_IN")
  ACAD_EXE="$P/drive_c/Program Files/Autodesk/AutoCAD 2027/acad.exe"
  [ -f "$ACAD_EXE" ] && ok "acad.exe installed" || hard "no acad.exe in $P (install into an empty prefix with tools/install_fresh_prefix.sh)" ""
  [ -f "$P/drive_c/Program Files/dotnet/dotnet.exe" ] && ok ".NET Desktop Runtime present" \
    || warn ".NET Desktop Runtime absent (acad's managed assemblies need it; --repair or the installer brings it)"
  [ -f "$P/drive_c/Program Files/Autodesk/AutoCAD 2027/AcJab.dll" ] && ok "acadprivate payload (AcJab.dll)" \
    || warn "AcJab.dll absent — licensing reports code 20001 branding error (that is the --repair path)"
  [ -f "$P/drive_c/Program Files/Autodesk/AutoCAD 2027/en-US/identity.ini" ] && ok "en-US/identity.ini" \
    || warn "en-US/identity.ini absent — acad cannot resolve its registry root (--repair writes it)"
fi

# -------------------------------------------------------- summary ---------
printf '\n== summary\n'
if [ "$HARDFAIL" = 0 ]; then
  printf '  no blocking requirement missing\n'
else
  printf '  blocking requirements missing: yes (see the [MISSING] lines above)\n'
fi

if [ "${#HARD_PKGS[@]}" -gt 0 ]; then
  printf '\n  missing packages, as one command (Ubuntu/Debian):\n'
  printf '    sudo apt-get install %s\n' "$(printf '%s\n' "${HARD_PKGS[@]}" | sort -u | tr '\n' ' ')"
  printf '  (no sudo? the project it came from built rootless: apt-get download <pkg> + dpkg-deb -x <deb> root/,\n'
  printf '   then source env.sh - it prepends root/usr/bin when root/ exists)\n'
fi
if [ "${#SOFT_PKGS[@]}" -gt 0 ]; then
  printf '\n  optional packages (extra features, not required):\n'
  printf '    sudo apt-get install %s\n' "$(printf '%s\n' "${SOFT_PKGS[@]}" | sort -u | tr '\n' ' ')"
fi

printf '\n== what to do next\n'
if [ "${#STEPS[@]}" -eq 0 ]; then
  printf '  1. tools/install_fresh_prefix.sh ~/acad-prefix\n'
  printf '  2. tools/verify_fresh_prefix.sh ~/acad-prefix 240\n'
else
  i=0
  for s in "${STEPS[@]}"; do i=$((i + 1)); printf '  %d. %s\n' "$i" "$s"; done
  printf '  %d. tools/install_fresh_prefix.sh ~/acad-prefix      (empty prefix -> installed AutoCAD)\n' "$((i + 1))"
  printf '  %d. tools/verify_fresh_prefix.sh ~/acad-prefix 240   (launches acad, PASS/FAIL per check)\n' "$((i + 2))"
fi
printf '\n  full walkthrough: SETUP.md\n'
[ "$HARDFAIL" = 0 ] && printf '  ==> ready to build/install\n' || printf '  ==> fix the [MISSING] lines first\n'
exit "$HARDFAIL"
