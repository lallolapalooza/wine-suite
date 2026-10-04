#!/bin/bash
# Re-run configure + incremental make + make install after the dcomp/dxgi/ncrypt patch series landed.
# Object files already built are reused, so this is cheap.
# usage: rebuild.sh [jobs]
set -u
CCWS=/home/asdf/projects/capcut-wine
SRC=$CCWS/wine/wine-11.18
PREFIX=$CCWS/wine-install
JOBS=${1:-16}
cd "$SRC" || exit 1

export CC="ccache gcc" CXX="ccache g++"
export CFLAGS="-O2 -g0"
export LDFLAGS=""

# configure.ac gained a line (dlls/dcomp/tests); keep the shipped `configure` newer so make
# never tries to regenerate it (autoconf here is a different version than the tarball's).
touch configure aclocal.m4

echo "=== reconfigure $(date) ==="
./configure --enable-archs=x86_64 --prefix="$PREFIX" \
    --without-coreaudio --without-oss > "$CCWS/logs/configure2.log" 2>&1 \
  || { echo "CONFIGURE FAILED"; tail -40 "$CCWS/logs/configure2.log"; exit 1; }

echo "=== make -j$JOBS $(date) ==="
make -j"$JOBS" > "$CCWS/logs/make2.log" 2>&1 \
  || { echo "MAKE FAILED"; tail -60 "$CCWS/logs/make2.log"; exit 1; }

echo "=== make install $(date) ==="
make install > "$CCWS/logs/make_install2.log" 2>&1 \
  || { echo "INSTALL FAILED"; tail -40 "$CCWS/logs/make_install2.log"; exit 1; }

echo "=== BUILD OK $(date) ==="
"$PREFIX/bin/wine" --version
touch "$CCWS/logs/.build_ok"
