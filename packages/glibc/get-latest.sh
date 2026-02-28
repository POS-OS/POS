#!/usr/bin/env bash

set -euo pipefail

base=$(git rev-parse --show-toplevel)

package=glibc

cd "$base/../upstream/$package" || exit 1
git checkout master
git pull
rsync --delete --delete-excluded --exclude .idea --exclude .git -av ./ "$base/src/$package/"
ucm=$(git log -1)

cd "$base" || exit 1
git add -A "src/$package"
git commit --author="pos-bot <pos-bot@devzero.dk>" -m "Glibc sources updated from upstream
---
$ucm"
