#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

# No logind support (pam_issue, pam_limits, pam_timestamp): systemd requires
# pam, so pam cannot link libsystemd. Where systemd is in /pos (an
# environment that has it for another reason), auto would link it.
meson setup "$build_dir" "$src_dir" \
      --prefix="$prefix" \
      --libdir=lib \
      --sysconfdir="$sysconfdir" \
      --buildtype=plain \
      -Dvendordir="${prefix}/share/pam" \
      -Dselinux=disabled \
      -Daudit=disabled \
      -Dlogind=disabled \
      -Delogind=disabled \
      -Ddocs=disabled
meson compile -C "$build_dir" -j "$nproc"
DESTDIR="$dest_dir" meson install -C "$build_dir"

pkg_finish
