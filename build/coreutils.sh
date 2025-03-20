#!/usr/bin/env bash

set -euo pipefail

component=coreutils

base=$(cd "$(dirname "$0")/../" || exit 1; pwd)
out_dir=${base}/work/output

mkdir -p "$out_dir/$component"

cd "${base}/src/${component}" || exit 1

autoreconf -fiv
