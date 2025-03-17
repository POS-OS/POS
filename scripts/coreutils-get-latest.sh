#!/usr/bin/env bash

base=$(cd "$(dirname "$0")/.." || exit 1; pwd)

cd "${base}/../upstream/coreutils" || exit 1
git checkout master
git pull
rsync --delete --delete-excluded --exclude .idea --exclude .git -av ./ "${base}/src/coreutils/"
ucm=$(git log -1)

cd "$base" || exit 1
git add -A src/coreutils
git commit --author="pos-bot <pos-bot@devzero.dk>" -m "Coreutils sources updated from upstream
---
$ucm"
