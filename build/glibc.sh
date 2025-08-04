#!/usr/bin/env bash

set -euo pipefail

component=glibc

base=$(cd "$(dirname "$0")/../" || exit 1; pwd)
work_dir=${base}/work

source "$base/enable.sh"
echo "$PATH"

mkdir "$work_dir/$component"
mkdir "$work_dir/pos-$component"

cd "$work_dir/$component" || exit 1

# Likely not needed...
#export LDFLAGS=-Wl,--dynamic-linker=/pos/lib/ld-linux-x86-64.so.2

echo "rootsbindir=/pos/sbin" > configparms
"${base}/src/${component}/configure" --prefix=/pos                            \
                                     --disable-werror                         \
                                     --enable-kernel=5.4                      \
                                     --enable-stack-protector=strong          \
                                     --disable-nscd                           \
                                     libc_cv_slibdir=/pos/lib
make

make DESTDIR="$work_dir/pos-$component" install

cd ..
rm -rf "./$component"
