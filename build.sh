#!/usr/bin/env bash

base=$(cd "$(dirname "$0")" || exit 1; pwd)

cd "$base" || exit 1
mkdir -p out
cd out || exit 1
mkdir -p build
mkdir -p util-linux
cd util-linux || exit 1
"${base}/src/util-linux/autogen.sh"

"${base}/src/util-linux/configure" \
    --prefix=/pos \
    --disable-liblastlog2 \
    --disable-makeinstall-chown

make
make DESTDIR="${base}/out/build" install

cd ..
rm -rf util-linux
