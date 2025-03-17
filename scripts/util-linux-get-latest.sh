#!/usr/bin/env bash

base=$(cd "$(dirname "$0")/.." || exit 1; pwd)

cd "${base}/../upstream/util-linux" || exit 1
git checkout master
git pull
rsync --delete --delete-excluded --exclude .idea --exclude .git -av ./ "${base}/src/util-linux/"
ucm=$(git log -1)

cd "$base" || exit 1
git add -A src/util-linux
git commit --author="pos-bot <pos-bot@devzero.dk>" -m "Util-linux sources updated from upstream
---
$ucm"
