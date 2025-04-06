#!/usr/bin/env bash

set -euo pipefail

base=$(cd "$(dirname "$0")/.." || exit 1; pwd)
component=dbus

cd "${base}/../upstream/${component}" || exit 1
git checkout main
git pull
rsync --delete --delete-excluded --exclude .idea --exclude .git -av ./ "${base}/src/${component}/"
ucm=$(git log -1)

cd "$base" || exit 1
git add -A src/${component}
git commit --author="pos-bot <pos-bot@devzero.dk>" -m "${component} sources updated from upstream
---
$ucm"
