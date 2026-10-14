#!/usr/bin/env bash
# Install the stage archives of a build as /pos-<id> and point /pos at it.
#
#   install.sh [<id>]    (default: the current build)

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../buildsys/buildinfo.sh
source "$base/buildsys/buildinfo.sh"
builds=${base}/work/builds

id=${1:-$(basename "$(readlink "${builds}/current")")}
bdir=${builds}/${id}

archives=()
for s in "${base}"/stages/*/; do
  a=${bdir}/pos-$(basename "$s")-$(build_stem "$bdir").tar.zst
  [[ -f $a ]] && archives+=("$a")
done
if ((${#archives[@]} == 0)); then
  echo "no archives in ${bdir}" >&2
  exit 1
fi

rm -rf "${bdir}/install"
mkdir "${bdir}/install"
for a in "${archives[@]}"; do
  tar --zstd -xpf "$a" -C "${bdir}/install"
done
sudo cp -a "${bdir}/install/pos" "/pos-${id}"
sudo ln -sfn "/pos-${id}" /pos
rm -rf "${bdir}/install"
