#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# awk is gawk on POS (BUILD.md "System stage"). -M uses gmp and mpfr
# from core-libs.
./configure --prefix="$prefix" \
            --sysconfdir="$sysconfdir"
make -j"$nproc"
make DESTDIR="$dest_dir" install

rm -f "${dest_dir}${prefix}/bin/gawkbug" \
      "${dest_dir}${prefix}/share/man/man1/gawkbug.1"

pkg_finish
