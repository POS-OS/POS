#!/usr/bin/env bash

set -euo pipefail

component=coreutils

base=$(cd "$(dirname "$0")/../" || exit 1; pwd)
work_dir=${base}/work

mkdir "$work_dir/pos-$component"
#mkdir "$work_dir/$component"

cd "${base}/src/${component}" || exit 1

git clean "${base}/src/${component}" -fdx

# src/coreutils/README-hacking bootstrap
make -f cfg.mk

## RPM:
## FIXME: Force a newer gettext version to workaround `autoreconf -i` errors
## with coreutils 9.6 and bundled gettext 0.19.2 from gettext-common-devel.
sed -i 's/0.19.2/0.22.5/' bootstrap.conf configure.ac

#autoreconf -fiv

#cd "$work_dir/$component" || exit 1

export LDFLAGS="-Wl,--dynamic-linker=/pos/lib/ld-linux-x86-64.so.2 -Wl,--rpath=/pos/lib"

./configure \
            --prefix=/pos            \
            --enable-no-install-program=kill,uptime \
            --enable-install-program=arch \
            --disable-systemd \
            --with-tty-group \
            --without-selinux \
            --without-openssl

##make CFLAGS="-fno-strict-aliasing -fpic -Dlint"
make
make DESTDIR="$work_dir/pos-$component" install
