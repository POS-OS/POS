#!/usr/bin/env bash
# The sdk compiler. The run-time libraries C and C++ programs need go to the
# gcc-runtime output, so a base system can ship them without the compiler.

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
source "$POS_BASE/packages/gcc/pos-defaults.sh"
require_container
pkg_setup
pkg_sync_src

gcc_pos_build

# gcc-runtime: libgcc_s, libstdc++, libatomic and libgomp, split as Fedora
# splits them. The output keeps what programs load at run time (lib*.so.N)
# and the libstdc++ gdb pretty-printers. Everything used only when
# compiling or linking stays with gcc: headers, the compiler's own
# directory (lib/gcc: crt files, libgcc.a, unwind.h, omp.h), static
# libraries, the unversioned lib*.so names the linker looks up,
# libgomp.spec and libstdc++.modules.json. pkg_finish removes what the
# output holds from gcc.
runtime=$(pkg_output gcc-runtime)
make DESTDIR="$runtime" install-target-libgcc install-target-libatomic \
     install-target-libstdc++-v3 install-target-libgomp
rm -rf "${runtime}${prefix}/include" "${runtime}${prefix}/lib/gcc"
find "${runtime}${prefix}/lib" -maxdepth 1 ! -type d ! -name 'lib*.so.*' -delete
# libtool archives: not needed to link against the shared libraries, and
# Fedora does not ship them.
find "${dest_dir}${prefix}/lib" -maxdepth 1 -name '*.la' -delete

pkg_finish
