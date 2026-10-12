#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1
# pam_cap is built with Linux-PAM later.
make prefix="$prefix" lib=lib GOLANG=no PAM_CAP=no -j"$nproc"
make prefix="$prefix" lib=lib GOLANG=no PAM_CAP=no DESTDIR="$dest_dir" install

pkg_finish
