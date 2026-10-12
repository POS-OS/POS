#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
./config --prefix="$prefix" \
         --openssldir="${sysconfdir}/ssl" \
         --libdir=lib \
         shared \
         zlib-dynamic
make -j"$nproc"
make DESTDIR="$dest_dir" MANSUFFIX=ssl install

pkg_finish
