#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# Git checkouts lack generated files such as libdw/known-dwarf.h; maintainer
# mode regenerates them (needs flex, bison, gawk).
./configure --prefix="$prefix" \
            --sysconfdir="$sysconfdir" \
            --enable-maintainer-mode \
            --disable-debuginfod \
            --enable-libdebuginfod=dummy \
            --disable-static
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
