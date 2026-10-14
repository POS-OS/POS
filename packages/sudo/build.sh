#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# sudoers, sudo.conf and sudoers.d install to /etc and move to the factory
# tree. Runtime state is /run/sudo, timestamps in /var/db/sudo. The install
# runs unprivileged, so ownership is not applied here. The secure_path of
# sudoers is the default one with POS's bin directories after it, as
# systemd's search path (packages/systemd).
./configure --prefix="$prefix" \
            --libexecdir="${prefix}/libexec" \
            --sysconfdir="$sysconfdir" \
            --with-rundir=/run/sudo \
            --with-vardir="${localstatedir}/db/sudo" \
            --with-tzdir="${prefix}/share/zoneinfo" \
            --with-secure-path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${prefix}/sbin:${prefix}/bin" \
            --with-env-editor \
            --with-pam \
            --with-passprompt="[sudo] password for %p: " \
            --disable-log-server \
            --disable-log-client \
            --without-selinux
make -j"$nproc"
make DESTDIR="$dest_dir" install install_uid="$(id -u)" install_gid="$(id -g)"

pkg_setuid "${prefix}/bin/sudo"

pkg_finish
