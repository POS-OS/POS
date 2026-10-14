#!/usr/bin/env bash
# Imports an image archive of a build into podman.
#
#   import-image.sh [-i <image>] [<id>]    (default: container, the current build)
#
# images/container is tagged pos:<id> and pos:latest, another image
# pos-<image without container->:<id> and :latest (container-dnf: pos-dnf).

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../buildsys/buildinfo.sh
source "$base/buildsys/buildinfo.sh"
builds=${base}/work/builds

image=container
if [[ ${1:-} == -i ]]; then
  image=${2:?}
  shift 2
fi
id=${1:-$(basename "$(readlink "${builds}/current")")}
bdir=${builds}/${id}

# POS programs are in /pos/bin and /pos/sbin. The dnf image is a Fedora
# layout: it links most of them into /usr/bin, except where a Fedora
# package has the path, so /usr/bin comes first there.
name=pos
path=/pos/bin:/pos/sbin:/usr/local/bin:/usr/bin
if [[ $image != container ]]; then
  name=pos-${image#container-}
  path=/usr/local/bin:/usr/bin:/pos/bin:/pos/sbin
fi

podman import --change "ENV PATH=$path" \
  --change 'CMD ["/usr/bin/bash"]' \
  "${bdir}/pos-image-${image}-$(build_stem "$bdir").tar.zst" "${name}:${id}"
podman tag "${name}:${id}" "${name}:latest"
