#!/usr/bin/env bash

set -euo pipefail

package=glibc

base=$(git rev-parse --show-toplevel)
work_dir=${base}/work

mkdir "$work_dir/$package"
mkdir "$work_dir/pos-$package"

cd "$work_dir/$package" || exit 1

echo "rootsbindir=/pos/sbin" > configparms
"${base}/src/${package}/configure" --prefix=/pos                            \
                                   --disable-werror                         \
                                   --enable-kernel=5.4                      \
                                   --enable-stack-protector=strong          \
                                   --disable-nscd                           \
                                   libc_cv_slibdir=/pos/lib
make

make DESTDIR="$work_dir/pos-$package" install

cd ..
rm -rf "./$package"
