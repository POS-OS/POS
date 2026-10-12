#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# journald rotates its own journal; logrotate is for everything else.
# Compression tools are the POS gzip. No logrotate.conf or units are
# installed by upstream; those come with the POS integration files.
./configure --prefix="$prefix" \
            --sysconfdir="$sysconfdir" \
            --with-state-file-path="${localstatedir}/lib/logrotate/logrotate.status" \
            --with-compress-command="${prefix}/bin/gzip" \
            --with-uncompress-command="${prefix}/bin/gunzip" \
            --with-acl \
            --without-selinux
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
