#!/usr/bin/env bash
# The sdk compiler. The run-time libraries C and C++ programs need go to the
# gcc-runtime output, so a base system can ship them without the compiler.

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
# The gcc source, with gmp, mpfr and mpc (meta with-sources) beside its
# own directories, where gcc's configure builds them along with it.
pkg_sync_src

# POS is a prefix (/pos) on a root that has no /lib or /usr/include of its
# own, so the compiler's built-in defaults must point there. --with-sysroot
# is the wrong tool: it treats /pos as a whole root, re-roots absolute paths
# in glibc's libc.so linker script to /pos/pos/lib, and leaves the ELF
# interpreter at /lib64/ld-linux-x86-64.so.2. Instead, patch the target
# header the way LFS pass 1 aims a compiler at /tools.
cd "$build_dir" || exit 1
hdr=gcc/config/i386/linux64.h
sed -e '/m64=/s/lib64/lib/' -i gcc/config/i386/t-linux64
sed -e 's@/lib64/ld-linux-x86-64.so.2@/pos/lib/ld-linux-x86-64.so.2@' -i "$hdr"
cat >> "$hdr" <<'EOF2'

/* POS: link against /pos/lib only. */
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/pos/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""
EOF2
# mpc's development branch makes mpc.h at configure time (from mpc.h.in),
# in mpc's build directory; gcc's configure looks for the in-tree mpc.h in
# the source directory only, where a release tarball has it.
sed -e "s|gmpinc='-I\\\$\\\$s/mpc/src |gmpinc='-I\$\$r/\$(HOST_SUBDIR)/mpc/src -I\$\$s/mpc/src |" -i configure
grep -q 'mpc/src -I\$\$s/mpc/src' configure || { echo "gcc: in-tree mpc include not patched" >&2; exit 1; }

# gcc's top-level configure derives CFLAGS_FOR_TARGET from CFLAGS, so the
# flags of pkg_flags would reach libgcc, libstdc++ and the other target
# libraries, which choose their own (libgcc is built without the stack
# protector). The compiler is built with the optimization and debug info
# only, as upstream's default -g -O2; the link flags stay.
export CFLAGS=$pos_optflags CXXFLAGS=$pos_optflags

# The compiler's own programs (cc1, cc1plus, lto1, collect2) run under the
# POS loader like everything else in /pos, so the ambient /pos link flags
# from pkg_setup stay on. The target libraries are built by the new xgcc
# with the patched defaults.
#
# What the compiler runs on is glibc only: gmp, mpfr and mpc from the tree,
# gcc's bundled zlib, no zstd (LTO streams are zlib-compressed), and
# libstdc++ and libgcc linked statically.
# --with-as/--with-ld bake the POS binutils paths into the driver.
# --without-isl pins the Graphite check so a change to the tools image
# cannot change the result. libcc1 installs into the building compiler's
# multilib directory (libcc1/configure.ac: $CXX -print-multi-os-directory),
# which Fedora's g++ answers with ../lib64; it is gdb's compile plugin.
mkdir build
cd build
../configure --prefix=/pos \
             --libdir=/pos/lib \
             --libexecdir=/pos/libexec \
             --with-slibdir=/pos/lib \
             --with-local-prefix=/pos \
             --with-native-system-header-dir=/pos/include \
             --enable-languages=c,c++ \
             --enable-default-pie \
             --enable-default-ssp \
             --enable-linker-build-id \
             --disable-multilib \
             --disable-bootstrap \
             --disable-nls \
             --disable-libstdcxx-pch \
             --disable-fixincludes \
             --disable-libcc1 \
             --with-static-standard-libraries \
             --without-zstd \
             --with-as=/pos/bin/as \
             --with-ld=/pos/bin/ld \
             --without-isl
make -j"$nproc"
make DESTDIR="$dest_dir" install

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

# The compiler's programs must run on glibc alone (see configure above).
# A configure check that quietly fell back to a shared library would tie
# the toolchain to a pos build's copy of it.
bad=$(find "${dest_dir}${prefix}/bin" "${dest_dir}${prefix}/libexec/gcc" -type f -perm -u+x \
        -exec readelf -d {} + 2>/dev/null |
      awk '/NEEDED/ {print $NF}' | tr -d '[]' | sort -u |
      grep -v -E '^(libc|libm|ld-linux-x86-64)\.so' || true)
if [[ -n $bad ]]; then
  echo "gcc: compiler programs need more than glibc: $(xargs <<<"$bad")" >&2
  exit 1
fi

pkg_finish
