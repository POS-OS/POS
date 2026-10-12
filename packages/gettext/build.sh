#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

# Only the runtime is part of the base image: gettext, ngettext and envsubst
# for shell scripts. libintl itself comes from glibc. The translation tools
# (msgfmt, xgettext, autopoint) are build-time and belong to the sdk stage.
cd "${build_dir}/gettext-runtime" || exit 1
./configure --prefix="$prefix" \
            --disable-static \
            --disable-java \
            --disable-csharp \
            --disable-libasprintf
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
