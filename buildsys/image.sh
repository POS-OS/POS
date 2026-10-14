#!/usr/bin/env bash
# Make an image of a build: a root filesystem archive with POS installed.
# Run by buildsys/build.sh after the stages are assembled.
#
#   image.sh <build dir> <image>
#
# images/<image>/layout names the stages and the root layout around /pos.
# The archive is <build dir>/pos-image-<image>-<stem>.tar.zst (stem:
# buildinfo.sh), owned by root.
# The tree is left at <build dir>/image/<image>.

set -euo pipefail
export LC_ALL=C

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=buildinfo.sh
source "$base/buildsys/buildinfo.sh"
bdir=${1:-}
image=${2:-}

if [[ -z $bdir || -z $image ]]; then
  echo "usage: $0 <build dir> <image>" >&2
  exit 1
fi

layout=${base}/images/${image}/layout
if [[ ! -f $layout ]]; then
  echo "unknown image: $image (missing $layout)" >&2
  exit 1
fi

stem=$(build_stem "$bdir")
root=${bdir}/image/${image}
archive=${bdir}/pos-image-${image}-${stem}.tar.zst

rm -rf "$root"
mkdir -p "$root"

while read -r kind path arg; do
  case $kind in
    ''|'#'*) continue ;;
    stage)
      a=${bdir}/pos-${path}-${stem}.tar.zst
      [[ -f $a ]] || { echo "stage $path is not assembled in $bdir" >&2; exit 1; }
      tar --zstd -xpf "$a" -C "$root"
      ;;
    dir) install -d -m "$arg" "$root$path" ;;
    link)
      install -d -m 0755 "$root$(dirname "$path")"
      ln -sfn "$arg" "$root$path"
      ;;
    *) echo "$layout: unknown entry: $kind" >&2; exit 1 ;;
  esac
done < "$layout"

# Shipped defaults, from the factory tree (BUILD.md "Prefix").
"$base/buildsys/image-factory.sh" "$root"

# Users and groups from the packages' sysusers.d, created by POS
# systemd-sysusers run through the POS loader, so /pos need not be
# installed where this runs.
SYSTEMD_LOG_LEVEL=warning "$root/pos/lib/ld-linux-x86-64.so.2" \
  --library-path "$root/pos/lib:$root/pos/lib/systemd" \
  "$root/pos/bin/systemd-sysusers" --root="$root"
rm -f "$root/etc/.pwd.lock"

# Nothing in the image is group-writable except the sticky directories
# (/tmp). Build trees can carry group write from the umask or default ACLs
# of the build directory.
find "$root" ! -type l -perm -g=w ! -perm -1000 -exec chmod g-w {} +

# Files the owner cannot read (/etc/shadow, mode 0000) are made readable to
# archive them and appended with their own mode.
tar=${archive%.zst}.tmp
locked=() modes=()
while read -r mode f; do
  locked+=("$f")
  modes+=("$mode")
done < <(cd "$root" && find . ! -type l ! -perm -u=r -printf '%m %p\n')
for f in "${locked[@]}"; do
  chmod u+r "$root/$f"
done
tar --owner=0 --group=0 --numeric-owner --sort=name --anchored \
  "${locked[@]/#/--exclude=}" -cf "$tar" -C "$root" .
for i in "${!locked[@]}"; do
  tar --owner=0 --group=0 --numeric-owner --mode="0${modes[i]}" \
    -rf "$tar" -C "$root" "${locked[i]}"
done
zstd -q -f --rm -o "$archive" "$tar"
echo "$archive"
