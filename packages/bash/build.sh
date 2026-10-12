#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# bash is /bin/sh on POS (BUILD.md "System stage"). Link the readline built
# in core-libs instead of the bundled copy.
./configure --prefix="$prefix" \
            --sysconfdir="$sysconfdir" \
            --without-bash-malloc \
            --with-installed-readline
make -j"$nproc"
make DESTDIR="$dest_dir" install

ln -sfn bash "${dest_dir}${prefix}/bin/sh"
rm -f "${dest_dir}${prefix}/bin/bashbug" \
      "${dest_dir}${prefix}/share/man/man1/bashbug.1"

pkg_finish
