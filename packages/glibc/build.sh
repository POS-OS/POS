#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=../../buildsys/pkg.sh
source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

cd "$build_dir" || exit 1

# glibc chooses its own flags for what it builds (-fno-stack-protector
# where needed, its stack protector and CET options below) and is linked
# by its own rules; the flags of pkg_flags are not for it. --enable-cet
# defaults to the compiler's default, which is off: without it crt1.o,
# crti.o and libc lack the CET property, and so does every program linked
# with them, whatever -fcf-protection it was compiled with.
export CFLAGS=$pos_optflags CXXFLAGS=$pos_optflags
unset LDFLAGS

# The POS loader and ldconfig use their own cache and configuration, not
# /etc/ld.so.cache and /etc/ld.so.conf. Those belong to the loader of
# whatever else is on the machine (a kept /usr, or the build container's
# Fedora), and listing both sets of libraries in one cache makes either
# loader pick up the other's libc. With no POS cache present, the loader
# searches /pos/lib. LD_SO_CACHE and LD_SO_CONF are only defaulted when
# not already defined (sysdeps/generic/dl-cache.h, elf/ldconfig.c).
#
# x86-64 rewrites ldd's loader list for a lib/lib64 multilib layout, which
# turns /pos/lib into /pos/lib64. POS has one /pos/lib; ldd lists only
# the loader that is installed. configparms is read after config.make.
cat > configparms <<'EOF2'
rootsbindir=/pos/sbin
config-extra-cppflags += -DLD_SO_CACHE='"/etc/pos/ld.so.cache"' -DLD_SO_CONF='"/etc/pos/ld.so.conf"'
ldd-rewrite-script = no
EOF2
"${src_dir}/configure" --prefix=/pos \
                       --sysconfdir="$sysconfdir" \
                       --localstatedir="$localstatedir" \
                       --disable-werror \
                       --enable-kernel=5.4 \
                       --enable-stack-protector=strong \
                       --enable-cet \
                       --disable-nscd \
                       libc_cv_slibdir=/pos/lib
make -j"$nproc"

make DESTDIR="$dest_dir" install
# C.UTF-8, the one locale a system needs whatever its language: programs
# that require UTF-8 fall back to it (tmux), and containers set it. Built
# by the new localedef as files, /pos/lib/locale/C.utf8, as Fedora ships it
# (glibc-minimal-langpack). glibc reads locales only from its own prefix.
make DESTDIR="$dest_dir" SUPPORTED-LOCALES=C.UTF-8/UTF-8 localedata/install-locale-files
# ldconfig output, regenerated on the target; not a shipped default.
rm -f "${dest_dir}/etc/pos/ld.so.cache"

pkg_finish
