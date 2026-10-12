#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# cron.d, anacrontab and the spool directory layout install to /etc and /var
# and are moved to the factory tree. cronie ships no systemd units; those
# come with the POS integration files (BUILD.md "System stage").
./configure --prefix="$prefix" \
            --sysconfdir="$sysconfdir" \
            --localstatedir="$localstatedir" \
            --with-pam \
            --with-inotify \
            --enable-anacron \
            --enable-pie \
            --enable-relro \
            --without-selinux \
            --without-audit
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_setuid "${prefix}/bin/crontab"

pkg_finish
