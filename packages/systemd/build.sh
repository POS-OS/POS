#!/usr/bin/env bash

set -euo pipefail

source "$POS_BASE/buildsys/pkg.sh"
require_container
pkg_setup
pkg_sync_src


# prefix is where systemd looks for its own units, generators and binaries
# (the separate rootprefix option is gone). Configuration stays in /etc and
# state in /var.
#
# systemd bakes in paths to programs it execs, defaulting to /usr/bin or
# /usr/sbin. The *-path options move the ones POS ships: kmod from kmod,
# the rest from util-linux (BUILD.md "Prefix"). quotaon, quotacheck, kexec,
# loadkeys and setfont are not in POS and keep their dead defaults.
#
# Its pam.d files go where POS pam reads vendor configuration
# (VENDORDIR/pam.d, packages/pam sets VENDORDIR=/pos/share/pam); the meson
# default /pos/lib/pam.d is not on pam's search path.
#
# The boot loader (systemd-boot and the EFI stub) is built: bootctl installs
# it from /pos/lib/systemd/boot/efi. It is made with pyelftools, a build
# tool, so it needs no EFI library.
#
# Disabled: SysV compatibility (runlevel targets, legacy tmpfiles),
# documentation (docbook toolchain), and every feature whose library is
# not built yet (cryptsetup, curl, idn2, gnutls, p11-kit, fido2, tpm2,
# qrencode, microhttpd, xkbcommon, bpf, glib, lz4, selinux, apparmor, audit).
#
# Note for tmpfiles: a C line without a source copies from /usr/share/factory,
# which does not exist on POS. Lines shipped by POS give the source
# explicitly (/pos/share/factory/...).
meson setup "$build_dir/build" "$build_dir" \
      --prefix="$prefix" \
      --libdir=lib \
      --sysconfdir="$sysconfdir" \
      --localstatedir="$localstatedir" \
      --buildtype=plain \
      -Dmode=release \
      -Dsplit-bin=true \
      -Dcompat-sysv-interfaces=false \
      -Dkmod-path="${prefix}/bin/kmod" \
      -Dmount-path="${prefix}/bin/mount" \
      -Dumount-path="${prefix}/bin/umount" \
      -Dsulogin-path="${prefix}/sbin/sulogin" \
      -Dswapon-path="${prefix}/sbin/swapon" \
      -Dswapoff-path="${prefix}/sbin/swapoff" \
      -Dagetty-path="${prefix}/sbin/agetty" \
      -Dnologin-path="${prefix}/sbin/nologin" \
      -Ddefault-user-shell="${prefix}/bin/bash" \
      -Ddebug-shell="${prefix}/bin/sh" \
      -Dfallback-hostname=pos \
      -Dpamlibdir="${prefix}/lib/security" \
      -Dpamconfdir="${prefix}/share/pam/pam.d" \
      -Drpmmacrosdir=no \
      -Dman=disabled \
      -Dhtml=disabled \
      -Dtests=false \
      -Dinstall-tests=false \
      -Dbootloader=enabled \
      -Dukify=disabled \
      -Dkernel-install=true \
      -Dseccomp=enabled \
      -Dkmod=enabled \
      -Dpam=enabled \
      -Dacl=enabled \
      -Dblkid=enabled \
      -Dfdisk=enabled \
      -Dopenssl=enabled \
      -Delfutils=enabled \
      -Dpcre2=enabled \
      -Dzlib=enabled \
      -Dbzip2=enabled \
      -Dxz=enabled \
      -Dzstd=enabled \
      -Dlz4=disabled \
      -Dlibcryptsetup=disabled \
      -Dlibcurl=disabled \
      -Dlibidn2=disabled \
      -Dgnutls=disabled \
      -Dp11kit=disabled \
      -Dlibfido2=disabled \
      -Dtpm2=disabled \
      -Dqrencode=disabled \
      -Dmicrohttpd=disabled \
      -Dxkbcommon=disabled \
      -Dbpf-framework=disabled \
      -Dglib=disabled \
      -Ddbus=disabled \
      -Dselinux=disabled \
      -Dapparmor=disabled \
      -Daudit=disabled \
      -Dsmack=false \
      -Dima=false \
      -Dhomed=disabled \
      -Dremote=disabled \
      -Dimportd=disabled \
      -Dmountfsd=false \
      -Dnsresourced=false
meson compile -C "$build_dir/build" -j "$nproc"
DESTDIR="$dest_dir" meson install -C "$build_dir/build"

pkg_finish
