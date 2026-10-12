#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# grep -P uses the pcre2 from core-libs.
./configure --prefix="$prefix" \
            --enable-perl-regexp
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
