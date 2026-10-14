#!/usr/bin/env bash
# Make a bootable disk of an image of a build: its archive extracted, the
# image's systemd-boot installed into /boot, and the partitions of
# images/<image>/repart.d made by systemd-repart, without loop devices.
# Run by buildsys/build.sh as root of a container of the build's tools
# image, after the image's archive.
#
#   image-disk.sh <build dir> <image>
#
# The disk is <build dir>/pos-disk-<image>-<stem>.raw (stem:
# buildinfo.sh), a sparse file. Its partitions have the discoverable
# partition types: systemd finds the ESP and root by their type, so the
# image needs no fstab and no root= on the kernel command line. /boot is
# the ESP: the image's boot loader entries and kernels are written there
# (image-dnf.sh).

set -euo pipefail
export LC_ALL=C

[[ -f /run/.containerenv && ! -f /run/.toolboxenv && $(id -u) == 0 ]] || {
  echo "image-disk.sh must run as root of a build container (./build image)" >&2
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

stem=$(build_stem "$bdir")
root=${bdir}/image/${image}
archive=${bdir}/pos-image-${image}-${stem}.tar.zst
disk=${bdir}/pos-disk-${image}-${stem}.raw

rm -rf "$root"
mkdir -p "$root"
zstd -dc "$archive" | tar --numeric-owner -xpf - -C "$root"

# The image's systemd-boot, installed by its bootctl run through the
# image's loader (as image.sh runs sysusers), so /pos need not be installed
# where this runs. /boot is not a vfat file system here, as the ESP is when
# the system runs.
SYSTEMD_RELAX_ESP_CHECKS=1 "$root/pos/lib/ld-linux-x86-64.so.2" \
  --library-path "$root/pos/lib:$root/pos/lib/systemd" \
  "$root/pos/bin/bootctl" --root="$root" --esp-path=/boot install --no-variables

rm -f "$disk.tmp"
systemd-repart --empty=create --size=auto --offline=yes --dry-run=no \
  --root="$root" --definitions="$base/images/$image/repart.d" "$disk.tmp"
mv "$disk.tmp" "$disk"
rm -rf "$root"
echo "$disk"
