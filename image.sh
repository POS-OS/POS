#!/usr/bin/env bash

set -euo pipefail

base=$(cd "$(dirname "$0")" || exit 1; pwd)
ts=$(date --utc +%Y%m%d%H%M)
work_dir=${base}/work

cd "$work_dir" || exit 1

components="glibc
attr
libcap
gmp
util-linux
"

mkdir -p "pos-${ts}"
for component in $components
do
  cp -a "pos-$component/." "pos-${ts}/"
done
tar cf "../pos-${ts}.tar" -C "pos-${ts}" .
rm -rf "./pos-${ts}"

podman import "../pos-${ts}.tar" "pos:${ts}"
podman tag "pos:${ts}" pos
