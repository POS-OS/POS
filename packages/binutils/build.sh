#!/usr/bin/env bash
# Assembler and linker for the sdk compiler. gcc execs as and ld; without
# these the sdk gcc would call the build container's /usr/bin tools, whose
# ld searches /usr/lib64 on its own. --with-lib-path makes this ld
# search /pos/lib only, which closes the last route by which host libraries
# reach a POS binary.

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

cd "$build_dir" || exit 1
# Out-of-tree, as binutils requires. The tree also carries gdb; only the
# binutils parts are built. No debuginfod: binutils cannot require
# elfutils, which is built with the gcc that execs it; auto would link it
# wherever elfutils happens to be in /pos. The bundled zlib and no zstd,
# as for gcc: the toolchain runs on glibc only (BUILD.md "Toolchain").
"${src_dir}/configure" --prefix="$prefix" \
                       --libdir="${prefix}/lib" \
                       --sysconfdir="$sysconfdir" \
                       --with-lib-path="${prefix}/lib" \
                       --enable-shared \
                       --disable-static \
                       --enable-ld=default \
                       --enable-plugins \
                       --enable-64-bit-bfd \
                       --enable-new-dtags \
                       --enable-relro \
                       --enable-default-hash-style=gnu \
                       --without-zstd \
                       --without-debuginfod \
                       --disable-gdb \
                       --disable-gdbserver \
                       --disable-sim \
                       --disable-readline \
                       --disable-libdecnumber \
                       --disable-gprofng \
                       --disable-werror \
                       --disable-nls
# tooldir is where binutils puts the tools for a compiler of the target
# (<prefix>/<target>/bin, hard links of /pos/bin's) and ld's reference
# linker scripts. The POS compiler is given /pos/bin/as and ld
# (packages/gcc/build.sh), and ld has its default scripts built in: with
# tooldir the prefix itself, there is no /pos/x86_64-pc-linux-gnu, and the
# scripts are in /pos/lib/ldscripts.
make -j"$nproc" tooldir="$prefix"
make DESTDIR="$dest_dir" tooldir="$prefix" install

pkg_finish
