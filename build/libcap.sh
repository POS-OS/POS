#!/usr/bin/env bash

set -euo pipefail

component=libcap

base=$(cd "$(dirname "$0")/../" || exit 1; pwd)
work_dir=${base}/work
source "$base/enable.sh"
echo "$PATH"

mkdir "$work_dir/pos-$component"

cd "${base}/src/${component}" || exit 1

export LDFLAGS="-Wl,--dynamic-linker=/pos/lib/ld-linux-x86-64.so.2 -Wl,--rpath=/pos/lib"

make prefix=/pos lib=lib
make DESTDIR="$work_dir/pos-$component" prefix=/pos lib=lib install
