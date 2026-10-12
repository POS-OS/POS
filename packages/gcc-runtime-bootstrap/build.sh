#!/usr/bin/env bash
# libstdc++, libgcc_s and libatomic from the gcc sources, without the
# compiler, built by the Fedora compiler. gcc-bootstrap is linked by
# Fedora's g++ and runs on these: the POS loader cannot use Fedora's copies,
# and gcc-bootstrap cannot produce its own before it exists. Same step as
# LFS "Libstdc++ from GCC", plus libgcc, which that step assumes is already
# there, and libatomic, which the compiler links by default
# (-latomic_asneeded) and libstdc++ depends on. The released gcc-runtime is
# an output of the gcc build.

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
source "$POS_BASE/packages/gcc/pos-defaults.sh"
require_container
pkg_setup
pkg_sync_src

# No pos-link profile for this package (see its meta). The scratch
# compiler is discarded, and the target libraries are built by xgcc with
# the patched /pos defaults. LIBRARY_PATH would make that xgcc link the
# libgcc and libstdc++ already installed in /pos.
gcc_pos_flags
cd "$build_dir" || exit 1
gcc_pos_patch_defaults "$build_dir"
mkdir build
cd build
mapfile -t args < <(gcc_pos_configure_args)
../configure "${args[@]}"
make -j"$nproc" all-gcc all-target-libgcc all-target-libatomic all-target-libstdc++-v3
make DESTDIR="$dest_dir" install-target-libgcc install-target-libatomic install-target-libstdc++-v3

pkg_finish
