#!/bin/bash
# Incremental build of the patched Wine tree, for when the first build (and its configure)
# already exists.  A full first-time build is tools/build_wine.sh, which copies wine-11.18
# to wine/wine-11.18, configures it and installs the result into wine-install/.
#
# Override parallelism: JOBS=8 ./run_build.sh
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT/env.sh"
cd "$ROOT/wine/wine-11.18" || { echo "no build tree: run tools/build_wine.sh first" >&2; exit 1; }
exec make -j"${JOBS:-4}"
