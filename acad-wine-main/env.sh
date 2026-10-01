#!/bin/bash
# Build/test environment for the AutoCAD-2027-on-Wine project.
# Source this from the checkout root:   source env.sh
#
# Everything defaults to the checkout, so nothing here needs editing:
#   ACAD                this checkout
#   WINEROOT            the Wine build tree          (tools/build_wine.sh creates it)
#   WINEPREFIX_INSTALL  where the build is installed (wine-install/, NOT a Wine prefix)
#   ACAD_MEDIA          the Autodesk ODIS media      (Setup.exe + ODIS/; see SETUP.md)
#   ACAD_PREFIX         the historical reference prefix (optional)
#
# Override any of them in the environment before sourcing, e.g.
#   ACAD_MEDIA=/mnt/media/autocad DISP=:0 source env.sh
export ACAD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export WINEROOT=${WINEROOT:-$ACAD/wine/wine-11.18}          # the tree that gets built
export WINEPREFIX_INSTALL=${WINEPREFIX_INSTALL:-$ACAD/wine-install}
export WINEBUILD=$WINEPREFIX_INSTALL/bin/wine

# Autodesk install media (your own download; nothing Autodesk is redistributed here).
export ACAD_MEDIA=${ACAD_MEDIA:-$ACAD/installer}
export ACAD_INSTALLER=$ACAD_MEDIA                           # historical name
export ACAD_PREFIX=${ACAD_PREFIX:-$ACAD/prefix}             # optional reference prefix

# Optional private toolchain rootfs.  The project it came from built rootless out of a
# rootfs at root/ (apt-get download + dpkg-deb -x); that rootfs is not part of this
# repository.  Use it if you have one, otherwise the system toolchain is used as-is -
# tools/check_prereqs.sh tells you which packages are missing.
#
# NOTE: the rootfs variables are only exported when root/ actually exists.  Exporting
# M4/BISON_PKGDATADIR/PKG_CONFIG_PATH at a nonexistent tree makes bison and m4 fail in
# ways that look like a missing package.
if [ -d "$ACAD/root/usr/bin" ]; then
  export R=$ACAD/root
  export PATH=$R/usr/bin:$PATH
  export BISON_PKGDATADIR=$R/usr/share/bison
  export M4=$R/usr/bin/m4
  export PKG_CONFIG_PATH=$R/usr/lib/x86_64-linux-gnu/pkgconfig
  echo "env.sh: toolchain rootfs at $R (prepended to PATH)" >&2
else
  echo "env.sh: no toolchain rootfs at $ACAD/root; using the system toolchain" >&2
fi
