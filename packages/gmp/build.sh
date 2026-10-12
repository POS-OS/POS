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
./configure --prefix="$prefix" --disable-static --enable-cxx --enable-fat \
            "${configure_extra[@]}"
# Release tarballs ship doc/version.texi; a git tree does not, and automake
# deliberately leaves version.texi without a dependency on stamp-vti, so
# the info build fails unless stamp-vti is asked for first.
make -C doc stamp-vti
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
