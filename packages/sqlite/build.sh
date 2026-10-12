#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# --soname=legacy: libsqlite3.so.0, as releases before autosetup and
# Fedora have. Without it the library has no soname, and programs linked
# to it record the development link libsqlite3.so.
./configure --prefix="$prefix" --disable-static --enable-fts5 --soname=legacy
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
