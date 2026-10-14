#!/usr/bin/env bash
# Install a hosted kernel into a layout image of a build: the Fedora
# packages in images/<image>/kernel are downloaded and unpacked into the
# image's tree (no rpm in the image), then POS's kernel-install adds the
# kernel, as Fedora's scriptlet does on an RPM system: its plugins run
# depmod, dracut (the initramfs) and write the boot loader entry into
# /boot. Run by buildsys/build.sh as root of a container of the build's
# tools image, after image.sh; it needs the network for Fedora's
# repositories.
#
#   image-kernel.sh <build dir> <image>
#
# The image's archive, <build dir>/pos-image-<image>-<stem>.tar.zst, is
# replaced by one with the kernel.

set -euo pipefail
export LC_ALL=C

[[ -f /run/.containerenv && ! -f /run/.toolboxenv && $(id -u) == 0 ]] || {
  echo "image-kernel.sh must run as root of a build container (./build image)" >&2
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

list=${base}/images/${image}/kernel
mapfile -t pkgs < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$list" | xargs -n1)
((${#pkgs[@]})) || { echo "$list names no packages" >&2; exit 1; }

stem=$(build_stem "$bdir")
root=${bdir}/image/${image}
rpms=${bdir}/image/${image}.rpms
archive=${bdir}/pos-image-${image}-${stem}.tar.zst
fedora=$(rpm -E %fedora)

rm -rf "$root" "$rpms" "$root.boot"
mkdir -p "$root" "$rpms" "$root.boot"
zstd -dc "$archive" | tar --numeric-owner -xpf - -C "$root"

# The packages' payload, unpacked next to the tree and merged into it:
# their /lib/modules is the image's link to /usr/lib/modules, where POS's
# kmod looks, which tar does not write through. Files they create in
# scriptlets (/boot) are made by kernel-install below.
dnf -q download --releasever="$fedora" --destdir="$rpms" "${pkgs[@]}"
mkdir "$rpms/tree"
for f in "$rpms"/*.rpm; do
  rpm2archive - <"$f" | tar -xzf - -C "$rpms/tree"
done
rsync -a --keep-dirlinks "$rpms/tree/" "$root/"
rm -rf "$rpms"

mapfile -t kvers < <(ls "$root/usr/lib/modules")
((${#kvers[@]} == 1)) || { echo "$image: expected one kernel, found: ${kvers[*]}" >&2; exit 1; }

# As image-dnf.sh runs scriptlets: /proc, /sys and /dev for dracut and
# depmod, and /boot a file system of its own, as the ESP is when the system
# runs (kernel-install's entries name files relative to it). The mounts
# are in a mount namespace of their own; what was written to /boot is kept
# in <root>.boot and moved into the tree after.
export root kver=${kvers[0]}
unshare -m bash -euo pipefail -c '
mount -t proc proc "$root/proc"
mount --rbind /sys "$root/sys"
mount --rbind /dev "$root/dev"
mount -t tmpfs -o mode=0755 tmpfs "$root/boot"
chroot "$root" env PATH=/pos/bin:/pos/sbin \
  kernel-install add "$kver" "/usr/lib/modules/$kver/vmlinuz"
cp -a "$root/boot/." "$root.boot/"
'
cp -a "$root.boot/." "$root/boot/"
rm -rf "$root.boot" "$root/var/tmp/"*

# Owners are kept as numbers, as image.sh wrote them.
tar --numeric-owner --sort=name -C "$root" -cf - . | zstd -q -f -T0 -o "$archive.tmp"
mv "$archive.tmp" "$archive"
rm -rf "$root"
echo "$archive"
