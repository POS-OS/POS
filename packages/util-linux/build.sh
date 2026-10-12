#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# util-linux provides login, su, nologin, sulogin, chfn, chsh, runuser and
# kill (BUILD.md "System stage"). shadow keeps the account tools, so vipw and
# newgrp are left to it.
# more does without libmagic: util-linux does not require file.
# The install runs unprivileged: no chown/setuid at make install time, the
# set-uid programs are marked with pkg_setuid below.
./configure --prefix="$prefix" \
            --libdir="${prefix}/lib" \
            --sysconfdir="$sysconfdir" \
            --localstatedir="$localstatedir" \
            --runstatedir=/run \
            --disable-static \
            --disable-pylibmount \
            --without-python \
            --disable-makeinstall-chown \
            --disable-makeinstall-setuid \
            --disable-makeinstall-tty-setgid \
            --disable-vipw \
            --disable-newgrp \
            --disable-setpriv \
            --enable-fs-paths-default="${prefix}/sbin" \
            --without-selinux \
            --without-audit \
            --without-smack \
            --without-utempter \
            --without-econf \
            --without-libmagic \
            --with-systemdsystemunitdir="${prefix}/lib/systemd/system" \
            --with-tmpfilesdir="${prefix}/lib/tmpfiles.d" \
            --with-sysusersdir="${prefix}/lib/sysusers.d" \
            --with-bashcompletiondir="${prefix}/share/bash-completion/completions" \
            --with-systemd \
            "${configure_extra[@]}"
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_setuid "${prefix}/bin/su" "${prefix}/bin/mount" "${prefix}/bin/umount" \
           "${prefix}/bin/chfn" "${prefix}/bin/chsh"

pkg_finish
