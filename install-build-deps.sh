#!/usr/bin/env bash

# id -u build &>/dev/null || sudo useradd build
# add to group tty for util-linux chgrp
sudo dnf -y groupinstall "Development Tools"
sudo dnf -y install \
  fedpkg \
  rpm-build \
  gcc-c++ \
  texinfo \
  m4 \
  bison \
  flex \
  bison-devel \
  byacc \
  python3-pyyaml \
  python3-requests \
  python3-jinja2 \
  meson \
  ninja-build \
  gperf \
  libcap-devel \
  clang \
  libmount-devel \
  libfdisk-devel \
  libacl-devel \
  libpwquality-devel \
  pam-devel \
  libselinux-devel \
  audit-libs-devel \
  cryptsetup-devel \
  dbus-devel \
  acl \
  libacl-devel \
  gobject-introspection-devel \
  libblkid-devel \
  xz-devel \
  gettext \
  gettext-devel \
  rubygem-asciidoctor \
  libutempter-devel \
  systemd-devel \
  po4a
