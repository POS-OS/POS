#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup

# Reference dbus-daemon (BUILD.md "System stage"). Built after systemd so
# the units and libsystemd integration are in place. Session and system bus
# configuration installs to /etc/dbus-1 and is moved to the factory tree.
meson setup "$build_dir" "$src_dir" \
      --prefix="$prefix" \
      --libdir=lib \
      --sysconfdir="$sysconfdir" \
      --localstatedir="$localstatedir" \
      --buildtype=plain \
      -Druntime_dir=/run \
      -Dsystem_socket=/run/dbus/system_bus_socket \
      -Dsystem_pid_file=/run/dbus/pid \
      -Duser_session=true \
      -Dsystemd=enabled \
      -Dsystemd_system_unitdir="${prefix}/lib/systemd/system" \
      -Dsystemd_user_unitdir="${prefix}/lib/systemd/user" \
      -Dselinux=disabled \
      -Dapparmor=disabled \
      -Dlibaudit=disabled \
      -Dx11_autolaunch=disabled \
      -Ddoxygen_docs=disabled \
      -Dxml_docs=disabled \
      -Dducktype_docs=disabled \
      -Dqt_help=disabled \
      -Dmodular_tests=disabled
meson compile -C "$build_dir" -j "$nproc"
DESTDIR="$dest_dir" meson install -C "$build_dir"
# The empty /run/dbus it installs is made at run time: systemd makes it
# for dbus.socket's socket.
rm -rf "${dest_dir:?}/run"

pkg_setuid "${prefix}/libexec/dbus-daemon-launch-helper"

pkg_finish
