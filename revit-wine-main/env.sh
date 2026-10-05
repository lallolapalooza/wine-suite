#!/bin/bash
# Build/test environment for the Revit-2027-on-Wine fork.
# Source this from the checkout root:   source env.sh
#
# Everything defaults to the checkout except the prefix and the logs, which live in the
# sibling work directory (this repository holds code, patches and instructions only):
#
#   REVIT                this checkout (the fork)
#   WINEROOT             the Wine build tree           (tools/build_wine.sh creates it)
#   WINEPREFIX_INSTALL   where the build is installed  (wine-install/, NOT a Wine prefix)
#   REVIT_MEDIA          the Autodesk ODIS media        (Setup.exe + ODIS/; see SETUP.md)
#   REVIT_WORK           the work directory             (prefix + logs + evidence)
#   REVIT_PREFIX         the Wine prefix                ($REVIT_WORK/prefix)
#   REVIT_LOGS           installer/run logs             ($REVIT_WORK/logs)
#
# Override any of them in the environment before sourcing, e.g.
#   REVIT_WORK=/mnt/work/revit DISP=:0 source env.sh
export REVIT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export WINEROOT=${WINEROOT:-$REVIT/wine/wine-11.18}          # the tree that gets built
export WINEPREFIX_INSTALL=${WINEPREFIX_INSTALL:-$REVIT/wine-install}
export WINEBUILD=$WINEPREFIX_INSTALL/bin/wine

# Autodesk install media (your own download; nothing Autodesk is redistributed here).
export REVIT_MEDIA=${REVIT_MEDIA:-$REVIT/installer}

# Work directory: the Wine prefix, the ODIS logs and the evidence live here, not in the repo.
export REVIT_WORK=${REVIT_WORK:-$(dirname "$REVIT")/revit}
export REVIT_PREFIX=${REVIT_PREFIX:-$REVIT_WORK/prefix}
export REVIT_LOGS=${REVIT_LOGS:-$REVIT_WORK/logs}

# The display the UI runs on.  :2 is the project's Xvfb/VNC display (no portal approval).
export DISP=${DISP:-:2}

# Optional private toolchain rootfs (as in the AutoCAD project).  The rootfs variables are
# only exported when root/ actually exists: exporting M4/BISON_PKGDATADIR/PKG_CONFIG_PATH at
# a nonexistent tree makes bison and m4 fail in ways that look like a missing package.
if [ -d "$REVIT/root/usr/bin" ]; then
  export R=$REVIT/root
  export PATH=$R/usr/bin:$PATH
  export BISON_PKGDATADIR=$R/usr/share/bison
  export M4=$R/usr/bin/m4
  export PKG_CONFIG_PATH=$R/usr/lib/x86_64-linux-gnu/pkgconfig
  echo "env.sh: toolchain rootfs at $R (prepended to PATH)" >&2
else
  echo "env.sh: no toolchain rootfs at $REVIT/root; using the system toolchain" >&2
fi
