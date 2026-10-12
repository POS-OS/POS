#!/usr/bin/env bash
# Make an image of a build with dnf: a root filesystem with the packages
# in images/<image>/packages installed, the build's RPM packages from
# <build dir>/rpm and the rest from Fedora's repositories. Run by
# buildsys/build.sh as root of a container of the build's tools image, after
# rpm.sh.
#
#   image-dnf.sh <build dir> <image>
#
# The archive is <build dir>/pos-image-<image>-<id>.tar.zst, and the list
# of installed packages <build dir>/pos-image-<image>-<id>.packages. The
# tree is removed: its files belong to the users the packages create,
# which only the container's root can remove.

set -euo pipefail
export LC_ALL=C

[[ -f /run/.containerenv && ! -f /run/.toolboxenv && $(id -u) == 0 ]] || {
  echo "image-dnf.sh must run as root of a build container (./build image)" >&2
  exit 1
}

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
bdir=${1:-}
image=${2:-}

if [[ -z $bdir || -z $image ]]; then
  echo "usage: $0 <build dir> <image>" >&2
  exit 1
fi

list=${base}/images/${image}/packages
if [[ ! -f $list ]]; then
  echo "unknown image: $image (missing $list)" >&2
  exit 1
fi

id=$(basename "$bdir")
root=${bdir}/image/${image}
archive=${bdir}/pos-image-${image}-${id}.tar.zst
fedora=$(rpm -E %fedora)

pkgs=()
while read -r name; do
  name=${name%%#*}
  name=${name//[[:space:]]/}
  [[ -n $name ]] || continue
  f=${bdir}/rpm/${name}-${id}-1.x86_64.rpm
  if [[ $name == pos || $name == pos-* ]]; then
    [[ -f $f ]] || { echo "$image: no RPM package $name in ${bdir}/rpm" >&2; exit 1; }
    pkgs+=("$f")
  else
    pkgs+=("$name")
  fi
done <"$list"

rm -rf "$root"
dnf -y --installroot="$root" --releasever="$fedora" --use-host-config \
  --setopt=install_weak_deps=False install "${pkgs[@]}"
dnf -y -q --installroot="$root" --releasever="$fedora" --use-host-config clean all
# No package creates /tmp and /dev: on Fedora, systemd-tmpfiles and the
# image builders do. librepo (dnf) needs /tmp.
install -d -m 1777 "$root/tmp"
install -d -m 0755 "$root/dev"
rpm --root "$root" -qa --qf '%{name}-%{evr}.%{arch}\n' | sort >"${archive%.tar.zst}.packages"

# Owners are kept as numbers: the users exist in the image's /etc/passwd.
tar --numeric-owner --sort=name -C "$root" -cf - . | zstd -q -f -T0 -o "$archive.tmp"
mv "$archive.tmp" "$archive"
rm -rf "$root"
echo "$archive"
