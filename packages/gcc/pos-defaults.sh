#!/usr/bin/env bash
# Shared by the gcc, gcc-bootstrap and gcc-runtime-bootstrap recipes.
#
# POS is a prefix (/pos) on a root that has no /lib or /usr/include of its
# own, so the compiler's built-in defaults must point there. --with-sysroot
# is the wrong tool: it treats /pos as a whole root, re-roots absolute paths
# in glibc's libc.so linker script to /pos/pos/lib, and leaves the ELF
# interpreter at /lib64/ld-linux-x86-64.so.2. Instead, patch the target
# header the way LFS pass 1 aims a compiler at /tools.

gcc_pos_patch_defaults() {
  local src=$1
  local hdr=$src/gcc/config/i386/linux64.h

  sed -e '/m64=/s/lib64/lib/' -i "$src/gcc/config/i386/t-linux64"
  sed -e 's@/lib64/ld-linux-x86-64.so.2@/pos/lib/ld-linux-x86-64.so.2@' -i "$hdr"
  cat >> "$hdr" <<'EOF'

/* POS: link against /pos/lib only. */
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/pos/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""
EOF
}

gcc_pos_configure_args() {
  cat <<EOF
--prefix=/pos
--libdir=/pos/lib
--libexecdir=/pos/libexec
--with-slibdir=/pos/lib
--with-local-prefix=/pos
--with-native-system-header-dir=/pos/include
--enable-languages=c,c++
--enable-default-pie
--enable-default-ssp
--enable-linker-build-id
--disable-multilib
--disable-bootstrap
--disable-nls
--disable-libstdcxx-pch
--disable-fixincludes
--with-system-zlib
EOF
}

# gcc's top-level configure derives CFLAGS_FOR_TARGET from CFLAGS, so the
# flags of pkg_flags would reach libgcc, libstdc++ and the other target
# libraries, which choose their own (libgcc is built without the stack
# protector). The compiler is built with the optimization and debug info
# only, as upstream's default -g -O2; the link flags stay.
gcc_pos_flags() {
  export CFLAGS=$pos_optflags CXXFLAGS=$pos_optflags
}

# Configure, build and install the compiler into $dest_dir. Shared by
# packages/gcc and packages/gcc-bootstrap.
#
# The compiler's own programs (cc1, cc1plus, lto1, collect2) run under the
# POS loader like everything else in /pos, so the ambient /pos link flags
# from pkg_setup stay on. The target libraries are built by the new xgcc
# with the patched defaults.
gcc_pos_build() {
  local -a args
  gcc_pos_flags
  cd "$build_dir" || exit 1
  gcc_pos_patch_defaults "$build_dir"
  mkdir build
  cd build
  mapfile -t args < <(gcc_pos_configure_args)
  # --with-as/--with-ld bake the POS binutils paths into the driver.
  # --without-isl pins the Graphite check so a change to the tools image
  # cannot change the result.
  ../configure "${args[@]}" \
               --with-as=/pos/bin/as \
               --with-ld=/pos/bin/ld \
               --with-gmp=/pos \
               --with-mpfr=/pos \
               --with-mpc=/pos \
               --with-zstd=/pos \
               --without-isl \
               "${configure_extra[@]}"
  make -j"$nproc"
  make DESTDIR="$dest_dir" install
}
