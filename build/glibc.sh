#!/usr/bin/env bash

set -euo pipefail

component=glibc

base=$(cd "$(dirname "$0")/../" || exit 1; pwd)
work_dir=${base}/work

mkdir -p "$work_dir/$component"
mkdir -p "$work_dir/pos-$component"

cd "$work_dir/$component" || exit 1
echo "rootsbindir=/pos/sbin" > configparms
"${base}/src/${component}/configure" --prefix=/pos                            \
                                     --disable-werror                         \
                                     --enable-kernel=5.4                      \
                                     --enable-stack-protector=strong          \
                                     --disable-nscd                           \
                                     libc_cv_slibdir=/pos/lib
make

make DESTDIR="$work_dir/pos-$component" install
