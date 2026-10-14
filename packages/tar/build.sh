#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
./configure --prefix="$prefix" \
            --without-selinux
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
