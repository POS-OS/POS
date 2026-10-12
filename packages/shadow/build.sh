#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# shadow owns the account database tools (useradd, passwd, chage, gpasswd,
# newgrp/sg, vipw). login, su, nologin, chfn and chsh come from util-linux
# and groups from coreutils, so those are dropped below (BUILD.md "System
# stage"). --enable-vendordir records the factory path. Reading login.defs
# from there when /etc/login.defs is absent needs libeconf, which is not
# built yet.
./configure --prefix="$prefix" \
            --sysconfdir="$sysconfdir" \
            --disable-static \
            --with-libpam \
            --with-bcrypt \
            --with-yescrypt \
            --without-libbsd \
            --without-su \
            --without-selinux \
            --without-audit \
            --with-group-name-max-length=32 \
            --enable-vendordir="${prefix}/share/factory/etc"
make -j"$nproc"
make DESTDIR="$dest_dir" install

for f in login chfn chsh groups; do
  rm -f "${dest_dir}${prefix}/bin/${f}"
done
rm -f "${dest_dir}${prefix}/sbin/nologin"
# Man pages for those, and the ones man-pages provides (passwd.5, getspnam.3).
# The git tree carries only DocBook sources; roff pages are generated at
# release time and need xsltproc plus the DocBook toolchain (--enable-man),
# which POS leaves out like it does for systemd and dbus. So there is
# usually nothing here.
if [[ -d ${dest_dir}${prefix}/share/man ]]; then
  find "${dest_dir}${prefix}/share/man" -regextype posix-extended \
       -regex '.*/(login|chfn|chsh|groups|nologin)\.[18](\..*)?' -delete
  find "${dest_dir}${prefix}/share/man" -regextype posix-extended \
       -regex '.*/(getspnam\.3|passwd\.5)(\..*)?' -delete
fi

# expiry(1) was removed upstream; chage -l covers it.
pkg_setuid "${prefix}/bin/passwd" "${prefix}/bin/chage" "${prefix}/bin/gpasswd" \
           "${prefix}/bin/newgrp"

pkg_finish
