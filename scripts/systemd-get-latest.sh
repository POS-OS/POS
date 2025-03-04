#!/usr/bin/env bash

base=$(cd "$(dirname "$0")" || exit 1; pwd)

rsync --delete --exclude .git -av ../upstream/systemd/ src/systemd/
git add -A src/systemd
cd ../upstream/systemd || exit 1
ucm=$(git log -1)
cd "$base" || exit 1
git commit --author="pos-bot <pos-bot@devzero.dk>" -m "Systemd sources updated from upstream
---
$ucm"
