#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

icu_src=${src_dir}/icu4c/source
if [[ ! -x $icu_src/configure ]]; then
  echo "missing icu4c/source/configure in $src_dir" >&2
  exit 1
fi

cd "$build_dir" || exit 1
"$icu_src/configure" --prefix="$prefix"
make -j"$nproc"
make DESTDIR="$dest_dir" install

pkg_finish
