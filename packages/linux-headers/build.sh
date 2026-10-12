#!/usr/bin/env bash
# Kernel UAPI headers. glibc's installed headers include <linux/errno.h> and
# <asm/*.h>, and the compiler searches only /pos/include, so these must live
# in the prefix. src/linux is the subset of the kernel tree that
# headers_install needs. It builds out of tree (O=): the only compiled
# program is the build's own fixdep helper, made with Fedora's compiler.

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container

# pkg_setup without pkg_finish: there are only headers, nothing to strip
# or move to the factory tree. No compiler environment is required; kbuild
# does not read the CFLAGS pkg_setup exports.
pkg_setup

make -C "$src_dir" O="$build_dir" ARCH=x86_64 \
     INSTALL_HDR_PATH="${dest_dir}${prefix}" headers_install

pkg_cleanup
