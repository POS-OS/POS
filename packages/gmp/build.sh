#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# --enable-fat: gmp otherwise tunes for the build machine's CPU, and the
# archive is installed on other machines. --enable-cxx needs libstdc++ from
# gcc-runtime in /pos.
./configure --prefix="$prefix" --disable-static --enable-cxx --enable-fat
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
