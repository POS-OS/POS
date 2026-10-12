#!/usr/bin/env bash
# gcc built by the Fedora compiler against the bootstrap packages. Its
# run-time libraries come from gcc-runtime-bootstrap, built before it.

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
source "$POS_BASE/packages/gcc/pos-defaults.sh"
require_container
pkg_setup
pkg_sync_src

# libcc1 installs into the building compiler's multilib directory
# (libcc1/configure.ac: $CXX -print-multi-os-directory); Fedora's g++
# answers ../lib64. It is gdb's compile plugin, not needed to build gcc.
configure_extra=(--disable-libcc1)

gcc_pos_build

# The target libraries are built again here. gcc-runtime-bootstrap's are the
# ones gcc-bootstrap runs on and that builds with it link; a path belongs
# to one package, so its files are left out here, as gcc leaves
# gcc-runtime's out.
while read -r f; do
  rm -f "${dest_dir}${f}"
done </pos/lib/pos/packages/gcc-runtime-bootstrap/files

pkg_finish
