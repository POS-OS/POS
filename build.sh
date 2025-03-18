#!/usr/bin/env bash

set -eou

base=$(cd "$(dirname "$0")" || exit 1; pwd)

cd "$base" || exit 1
mkdir -p work/output
cd work || exit 1
mkdir -p util-linux
cd util-linux || exit 1
"${base}/src/util-linux/autogen.sh"
# $RPM_OPT_FLAGS?
export CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64"
export SUID_CFLAGS="-fpie"
export SUID_LDFLAGS="-pie -Wl,-z,relro -Wl,-z,now"
export DAEMON_CFLAGS="$SUID_CFLAGS"
export DAEMON_LDFLAGS="$SUID_LDFLAGS"

#--with-python=%{pyver} \
"${base}/src/util-linux/configure" \
    --prefix=/pos \
    --with-systemdsystemunitdir=/pos/lib/systemd \
    --with-tmpfilesdir=/pos/lib/tmpfiles.d \
    --with-sysusersdir=/pos/lib/sysusers.d \
    --without-user \
    --disable-silent-rules \
    --disable-bfs \
    --disable-pg \
    --disable-liblastlog2 \
    --enable-chfn-chsh \
    --enable-usrdir-path \
    --enable-write \
    --disable-raw \
    --enable-hardlink \
    --enable-fdformat \
    --enable-asciidoc \
    --with-systemd \
    --with-udev \
    --with-selinux \
    --with-audit \
    --with-utempter \
    --disable-makeinstall-chown

make
make DESTDIR="${base}/work/output" install

cd ..
rm -rf util-linux
