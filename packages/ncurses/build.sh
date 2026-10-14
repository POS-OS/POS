#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

cd "$build_dir" || exit 1
# The man page format is given: configure otherwise copies what it finds
# on the build host (gzip in Fedora). Terminal entries are looked up as
# Fedora's ncurses does, local ones in /etc first, with POS's before
# /usr/share/terminfo, where Fedora packages (foot-terminfo, kitty-terminfo,
# ncurses-term) install theirs.
"${src_dir}/configure" --prefix="$prefix" \
                       --mandir="${prefix}/share/man" \
                       --with-terminfo-dirs="/etc/terminfo:${prefix}/share/terminfo:/usr/share/terminfo" \
                       --with-manpage-format=normal \
                       --with-shared \
                       --without-debug \
                       --without-normal \
                       --with-cxx-shared \
                       --enable-pc-files \
                       --with-pkg-config-libdir="${prefix}/lib/pkgconfig"
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
