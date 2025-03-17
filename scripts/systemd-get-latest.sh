#!/usr/bin/env bash

base=$(cd "$(dirname "$0")/.." || exit 1; pwd)

cd "${base}/../upstream/systemd" || exit 1
rsync --delete --delete-excluded --exclude .idea --exclude .git -av ./ "${base}/src/systemd/"
ucm=$(git log -1)

cd "$base" || exit 1
git add -A src/systemd
git commit --author="pos-bot <pos-bot@devzero.dk>" -m "Systemd sources updated from upstream
---
$ucm"
