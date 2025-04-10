#!/usr/bin/env bash

[[ ! -f /run/.toolboxenv ]] && exit 1

# id -u build &>/dev/null || sudo useradd build
# add to group tty for util-linux chgrp
sudo dnf -y group install "development-tools"
sudo dnf -y install \
  acl \
  autoconf \
  audit-libs-devel \
  bison \
  bison-devel \
  byacc \
  clang \
  cryptsetup-devel \
  dbus-devel \
  fedpkg \
  flex \
  gcc-c++ \
  gettext \
  gettext-devel \
  gmp-devel \
  gobject-introspection-devel \
  gperf \
  libacl-devel \
  libacl-devel \
  libattr-devel \
  libcap-devel \
  libselinux-devel \
  libselinux-utils \
  libblkid-devel \
  libcap-devel \
  libfdisk-devel \
  libmount-devel \
  libpwquality-devel \
  libselinux-devel \
  libutempter-devel \
  m4 \
  meson \
  ninja-build \
  pam-devel \
  po4a \
  python3-jinja2 \
  python3-pyyaml \
  python3-requests \
  rpm-build \
  rubygem-asciidoctor \
  systemd-devel \
  texinfo \
  xz-devel \
  perl
