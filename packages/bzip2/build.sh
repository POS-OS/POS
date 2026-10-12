#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1

if [[ -f meson.build ]]; then
  meson setup build --prefix="$prefix" --libdir=lib --buildtype=plain
  meson compile -C build -j "$nproc"
  DESTDIR="$dest_dir" meson install -C build
elif [[ -f Makefile-libbz2_so ]]; then
  make -f Makefile-libbz2_so
  make clean
  make -j"$nproc"
  make PREFIX="${dest_dir}${prefix}" install
  mkdir -p "${dest_dir}${prefix}/lib"
  cp -a libbz2.so.* "${dest_dir}${prefix}/lib/"
else
  echo "unrecognized bzip2 build system" >&2
  exit 1
fi

pkg_finish
