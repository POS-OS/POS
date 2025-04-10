#!/usr/bin/env bash

set -euo pipefail

component=coreutils

base=$(cd "$(dirname "$0")/../" || exit 1; pwd)
work_dir=${base}/work

mkdir -p "$work_dir/$component"
mkdir -p "$work_dir/pos-$component"

cd "${base}/src/${component}" || exit 1

autoreconf -fv
automake -af

./configure \
            --prefix=/pos            \
            --enable-no-install-program=kill,uptime \
            --enable-install-program=arch \
            --enable-systemd \
            --with-tty-group \

make CFLAGS="-fno-strict-aliasing -fpic -Dlint"
#make DESTDIR="$out_dir/pos-$component" install
