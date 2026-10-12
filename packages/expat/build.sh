#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

# libexpat keeps the library in the expat/ subdirectory.
src_root=$build_dir
if [[ -d $build_dir/expat ]]; then
  src_root=$build_dir/expat
fi

cd "$src_root" || exit 1
# Symbol versions (lib/libexpat.map, LIBEXPAT_*) are off by default
# upstream. Fedora's libexpat has them, and binaries linked against it
# require them.
./configure --prefix="$prefix" --disable-static --docdir="${prefix}/share/doc/expat" \
            --enable-symbol-versioning
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
