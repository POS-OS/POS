#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src

cd "$build_dir" || exit 1

# Compile zic and zdump using the POS compiler and flags.
make -j"$nproc" CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

# Install zoneinfo data into /pos/share/zoneinfo and utilities into /pos/{bin,sbin}.
make DESTDIR="$dest_dir" \
     TOPDIR= \
     USRDIR="${prefix#/}" \
     USRSHAREDIR="${prefix#/}/share" \
     BINDIR="${prefix}/bin" \
     ZICDIR="${prefix}/sbin" \
     ZDUMPDIR="${prefix}/bin" \
     TZDIR="${prefix}/share/zoneinfo" \
     MANDIR="${prefix}/share/man" \
     LIBDIR="${prefix}/lib" \
     install

# Do not ship /etc/localtime in the base package; local time is configured per
# machine via timedatectl or system configuration.
rm -f "${dest_dir}/etc/localtime"

pkg_finish
