#!/usr/bin/env bash
# Make an image of a build with dnf: a root filesystem with the packages
# in images/<image>/packages installed, the build's RPM packages from
# <build dir>/rpm and the rest from Fedora's repositories. Files in
# images/<image>/root (configuration the packages' scriptlets read, such as
# /etc/kernel) are copied in first. Run by buildsys/build.sh as root of a
# container of the build's tools image, after rpm.sh.
#
#   image-dnf.sh <build dir> <image>
#
# The archive is <build dir>/pos-image-<image>-<stem>.tar.zst (stem:
# buildinfo.sh), and the list
# of installed packages <build dir>/pos-image-<image>-<stem>.packages. The
# tree is removed: its files belong to the users the packages create,
# which only the container's root can remove.

set -euo pipefail
export LC_ALL=C

[[ -f /run/.containerenv && ! -f /run/.toolboxenv && $(id -u) == 0 ]] || {
  echo "image-dnf.sh must run as root of a build container (./build image)" >&2
  exit 1
}

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=buildinfo.sh
source "$base/buildsys/buildinfo.sh"
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

stem=$(build_stem "$bdir")
evr=$(rpm_evr "$bdir")
root=${bdir}/image/${image}
archive=${bdir}/pos-image-${image}-${stem}.tar.zst
fedora=$(rpm -E %fedora)

pkgs=()
while read -r name; do
  name=${name%%#*}
  name=${name//[[:space:]]/}
  [[ -n $name ]] || continue
  f=${bdir}/rpm/${name}-${evr}.x86_64.rpm
  if [[ $name == pos || $name == pos-* ]]; then
    [[ -f $f ]] || { echo "$image: no RPM package $name in ${bdir}/rpm" >&2; exit 1; }
    pkgs+=("$f")
  else
    pkgs+=("$name")
  fi
done <"$list"

rm -rf "$root" "$root.boot"
mkdir -p "$root" "$root.boot"
# Owned by root, with modes of the umask (not the checkout's).
if [[ -d $base/images/$image/root ]]; then
  cp -R --no-preserve=mode,ownership "$base/images/$image/root/." "$root/"
fi

# Scriptlets run in the root as on a running system: kernel-install and
# depmod need /proc, dracut /sys and /dev. /boot is a file system of its
# own, as the ESP is when the system runs: kernel-install's boot loader
# entries name files relative to the file system /boot is on. The mounts
# are in a mount namespace of their own, gone when dnf is done; what was
# written to /boot is kept in <root>.boot and moved into the tree after.
export root fedora
unshare -m bash -euo pipefail -c '
for d in proc sys dev boot; do
  mkdir -p "$root/$d"
done
mount -t proc proc "$root/proc"
mount --rbind /sys "$root/sys"
mount --rbind /dev "$root/dev"
mount -t tmpfs -o mode=0755 tmpfs "$root/boot"
dnf -y --installroot="$root" --releasever="$fedora" --use-host-config \
  --setopt=install_weak_deps=False install "$@"
cp -a "$root/boot/." "$root.boot/"
' image-dnf "${pkgs[@]}"
cp -a "$root.boot/." "$root/boot/"
rm -rf "$root.boot"
dnf -y -q --installroot="$root" --releasever="$fedora" --use-host-config clean all
# No package creates /tmp: on Fedora, systemd-tmpfiles and the image
# builders do. librepo (dnf) needs it.
install -d -m 1777 "$root/tmp"
# Shipped defaults, from the factory tree (BUILD.md "Prefix"); dnf
# installs no files of POS's outside /pos.
"$base/buildsys/image-factory.sh" "$root"
rpm --root "$root" -qa --qf '%{name}-%{evr}.%{arch}\n' | sort >"${archive%.tar.zst}.packages"

# Owners are kept as numbers: the users exist in the image's /etc/passwd.
tar --numeric-owner --sort=name -C "$root" -cf - . | zstd -q -f -T0 -o "$archive.tmp"
mv "$archive.tmp" "$archive"
rm -rf "$root"
echo "$archive"
