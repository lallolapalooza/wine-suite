#!/bin/bash
# Configure + build + install the merged (acad+powerbi union) Wine 11.18 tree, x86_64-only.
# usage: build_wine.sh [jobs]
set -u
CCWS=/home/asdf/projects/capcut-wine
SRC=$CCWS/wine/wine-11.18
PREFIX=$CCWS/wine-install
JOBS=${1:-16}
cd "$SRC" || exit 1

export CC="ccache gcc" CXX="ccache g++"
export CFLAGS="-O2 -g0"
export LDFLAGS=""

if [ ! -f config.status ]; then
  echo "=== configure $(date) ==="
  ./configure --enable-archs=x86_64 --prefix="$PREFIX" \
      --without-coreaudio --without-oss \
      > "$CCWS/logs/configure.log" 2>&1 || { echo "CONFIGURE FAILED"; tail -40 "$CCWS/logs/configure.log"; exit 1; }
fi
echo "=== make -j$JOBS $(date) ==="
make -j"$JOBS" > "$CCWS/logs/make.log" 2>&1 || { echo "MAKE FAILED"; tail -60 "$CCWS/logs/make.log"; exit 1; }
echo "=== make install $(date) ==="
make install > "$CCWS/logs/make_install.log" 2>&1 || { echo "INSTALL FAILED"; tail -40 "$CCWS/logs/make_install.log"; exit 1; }
echo "=== BUILD OK $(date) ==="
"$PREFIX/bin/wine" --version
touch "$CCWS/logs/.build_ok"
