#!/usr/bin/env bash

set -euo pipefail

base=$(cd "$(dirname "$0")" || exit 1; pwd)

cd "$base" || exit 1

build=$1
mkdir work/install
tar -xf "${build}.tar" -C work/install
sudo cp -r work/install/pos "/$build"
sudo ln -sfn "/$build" /pos
rm -rf work/install
