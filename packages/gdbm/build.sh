#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# libgdbm-compat is the ndbm/dbm API man-db can use.
./configure --prefix="$prefix" \
            --disable-static \
            --enable-libgdbm-compat
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
