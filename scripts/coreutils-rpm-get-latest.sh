#!/usr/bin/env bash

set -euo pipefail

base=$(cd "$(dirname "$0")/.." || exit 1; pwd)

cd "${base}/../upstream/fedora/rpms/coreutils" || exit 1
git checkout pos-staging || exit 1
git fetch
git merge --squash origin/main
git commit --no-edit
