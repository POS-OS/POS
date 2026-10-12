#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# Data only. crypt(3) and friends are documented by libxcrypt, which is
# already in core-libs; drop the man-pages copies so the two do not clash.
rm -f man/man3/crypt*
make -R prefix="$prefix" DESTDIR="$dest_dir" install

pkg_finish
