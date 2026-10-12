#!/usr/bin/env bash
# Assemble a stage of a build into one archive. Run by buildsys/build.sh.
#
#   assemble.sh <build dir> <stage>
#
# The archive is <build dir>/pos-<stage>-<id>.tar.zst with a top-level pos/
# directory. The merged tree is left at <build dir>/assemble/<stage>/pos.
# The packages' separate debug info (pkg_strip in buildsys/pkg.sh) is
# archived the same way as <build dir>/pos-debug-<stage>-<id>.tar.zst,
# merged at <build dir>/assemble-debug/<stage>/pos; it extracts on top of
# the stage, into /pos/lib/debug.

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
bdir=${1:-}
stage=${2:-}

if [[ -z $bdir || -z $stage ]]; then
  echo "usage: $0 <build dir> <stage>" >&2
  exit 1
fi

list=${base}/stages/${stage}/packages
if [[ ! -f $list ]]; then
  echo "unknown stage: $stage (missing $list)" >&2
  exit 1
fi

id=$(basename "$bdir")
root=${bdir}/assemble/${stage}
archive=${bdir}/pos-${stage}-${id}.tar.zst
droot=${bdir}/assemble-debug/${stage}
darchive=${bdir}/pos-debug-${stage}-${id}.tar.zst

rm -rf "$root" "$droot" "$darchive"
mkdir -p "$root/pos" "$droot/pos"

while read -r package; do
  package=${package%%#*}
  package=${package//[[:space:]]/}
  [[ -z $package ]] && continue
  src=${bdir}/dest/${package}
  if [[ ! -f ${src}/pos/lib/pos/packages/${package}/meta ]]; then
    echo "${package} is not built in $bdir" >&2
    exit 1
  fi
  rsync -a "${src}/pos/" "$root/pos/"
  if [[ -d ${bdir}/debug/${package}/pos ]]; then
    rsync -a "${bdir}/debug/${package}/pos/" "$droot/pos/"
  fi
done < "$list"

# Everything in /pos is owned by root. Recording 0:0 here is what makes the
# set-uid bits set by pkg_setuid effective once extracted as root.
tar --zstd --owner=0 --group=0 -cf "$archive" -C "$root" pos
echo "$archive"
if [[ -n $(find "$droot/pos" -mindepth 1 -print -quit) ]]; then
  tar --zstd --owner=0 --group=0 -cf "$darchive" -C "$droot" pos
  echo "$darchive"
fi
