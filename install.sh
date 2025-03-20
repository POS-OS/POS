#!/usr/bin/env bash

set -euo pipefail

base=$(cd "$(dirname "$0")" || exit 1; pwd)

cd "$base" || exit 1

ts=$(date --utc +%Y%m%d%H%M)
sudo cp -r work/output/pos /pos-"$ts"
sudo ln -fs /pos-"$ts" /pos
