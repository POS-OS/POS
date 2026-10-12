#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# The magic database is compiled with the file binary built here, which is
# why file must be a native build. seccomp sandboxing uses libseccomp from
# this stage.
./configure --prefix="$prefix" \
            --disable-static \
            --enable-libseccomp \
            --enable-zlib \
            --enable-bzlib \
            --enable-xzlib \
            --enable-zstdlib \
            --disable-lzlib \
            --disable-lrziplib
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
