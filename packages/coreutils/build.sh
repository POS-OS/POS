#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# kill comes from util-linux and uptime from procps (BUILD.md "System stage").
# hostname is not installed by default; nothing else in the base provides it.
# libgmp gives expr and factor arbitrary precision. gmp is a core library.
./configure --prefix="$prefix" \
            --enable-no-install-program=kill,uptime \
            --enable-install-program=hostname \
            --with-openssl=yes \
            --with-libgmp \
            --with-libgmp-prefix="$prefix" \
            --without-selinux
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
