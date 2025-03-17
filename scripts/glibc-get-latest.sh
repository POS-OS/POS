#!/usr/bin/env bash

base=$(cd "$(dirname "$0")/.." || exit 1; pwd)

cd "${base}/../upstream/glibc" || exit 1
rsync --delete --delete-excluded --exclude .idea --exclude .git -av ./ "${base}/src/glibc/"
ucm=$(git log -1)

cd "$base" || exit 1
git add -A src/glibc
git commit --author="pos-bot <pos-bot@devzero.dk>" -m "Glibc sources updated from upstream
---
$ucm"
