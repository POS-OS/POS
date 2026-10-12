#!/usr/bin/env bash
# GNU which. which's own xmalloc is used: --disable-iberty would leave it
# undefined, so the libiberty check is answered instead.

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
./configure --prefix="$prefix" \
            ac_cv_lib_iberty_xmalloc=no
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
