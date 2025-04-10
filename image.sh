#!/usr/bin/env bash

set -euo pipefail

base=$(cd "$(dirname "$0")" || exit 1; pwd)
ts=$(date --utc +%Y%m%d%H%M)

cd "$base" || exit 1

components="glibc
"

for component in $components
do
  tar rvf work/pos-${ts}.tar -C work/pos-$component .
done

podman import work/pos-${ts}.tar pos:${ts}

podman tag pos:${ts} pos
