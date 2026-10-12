#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

# popt dropped autotools; the tree is CMake only. GNUInstallDirs would pick
# lib64 on the host, so libdir is pinned to lib.
cmake -S "$src_dir" -B "$build_dir" \
      -DCMAKE_BUILD_TYPE=None \
      -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_INSTALL_SYSCONFDIR="$sysconfdir"
cmake --build "$build_dir" -j "$nproc"
DESTDIR="$dest_dir" cmake --install "$build_dir"

pkg_finish
