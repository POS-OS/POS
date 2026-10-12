#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
./configure --prefix="$prefix" \
            --disable-static \
            --with-curses \
            --docdir="${prefix}/share/doc/readline"
make SHLIB_LIBS="-lncursesw" -j"$nproc"
make SHLIB_LIBS="-lncursesw" DESTDIR="$dest_dir" install

pkg_finish
