#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# groff formats man pages for man-db (nroff, troff, tbl, eqn). No X11
# previewers and no formatted documentation.
./configure --prefix="$prefix" \
            --sysconfdir="$sysconfdir" \
            --without-x \
            --with-doc=no
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
