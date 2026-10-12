#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

cd "$build_dir" || exit 1
# The programs Fedora's procps-ng has, uptime among them (coreutils leaves
# it out), skill and snice. kill is util-linux's (BUILD.md "System stage").
# w reads sessions from logind (--with-systemd), not utmp.
"${src_dir}/configure" --prefix="$prefix" \
                       --libdir="${prefix}/lib" \
                       --sysconfdir="$sysconfdir" \
                       --localstatedir="$localstatedir" \
                       --disable-static \
                       --disable-kill \
                       --enable-skill \
                       --enable-watch8bit \
                       --enable-sigwinch \
                       --with-systemd
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
