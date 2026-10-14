#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

# kmod searches /usr/lib/{modprobe,depmod}.d by default; distconfdir points
# that at the prefix. Modules stay in /usr/lib/modules: POS boots kernels
# other projects build, and their packages install modules there (as
# systemd's kernel-install expects).
meson setup "$build_dir" "$src_dir" \
      --prefix="$prefix" \
      --libdir=lib \
      --sysconfdir="$sysconfdir" \
      --buildtype=plain \
      -Ddistconfdir="${prefix}/lib" \
      -Dmoduledir=/usr/lib/modules \
      -Dopenssl=enabled \
      -Dmbedtls=disabled \
      -Dzlib=enabled \
      -Dxz=enabled \
      -Dzstd=enabled \
      -Dmanpages=false \
      -Ddocs=false \
      -Dbuild-tests=false
meson compile -C "$build_dir" -j "$nproc"
DESTDIR="$dest_dir" meson install -C "$build_dir"

pkg_finish
