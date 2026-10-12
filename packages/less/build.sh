#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# less is the pager for man and systemd. Regex matching uses core-libs pcre2.
./configure --prefix="$prefix" \
            --sysconfdir="$sysconfdir" \
            --with-regex=pcre2
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
