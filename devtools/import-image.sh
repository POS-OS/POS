#!/usr/bin/env bash
# Makes an image of a build available in podman, tagged with the build ID
# and with its version (BUILD, or <BUILD>u<UPDATE>), the tag to make
# containers and toolboxes from. The version tag moves to whichever build
# of that version was made available last. A build tags the images it
# makes with podman itself; this imports the others, or moves the version
# tag back to an earlier build:
#
#   import-image.sh [-i <image>] [<id>]    (default: container, the current build)
#   toolbox create -i localhost/pos-fedora-toolbox:<version>
#
# images/container is pos in podman, images/container-<x> and images/<x>
# are pos-<x> (container-dnf: pos-dnf). An image with an archive (layout,
# dnf) is imported from it. One made with podman (containerfile) is in
# podman since the build made it, and is only tagged.

set -euo pipefail

base=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../buildsys/buildinfo.sh
source "$base/buildsys/buildinfo.sh"
builds=${base}/work/builds

# The host's podman, from a toolbox too (as ./build).
podman() {
  if [[ -f /run/.toolboxenv ]]; then
    flatpak-spawn --host podman "$@"
  else
    command podman "$@"
  fi
}

image=container
if [[ ${1:-} == -i ]]; then
  image=${2:?}
  shift 2
fi
id=${1:-$(basename "$(readlink "${builds}/current")")}
bdir=${builds}/${id}
[[ -f $bdir/info ]] || { echo "no build $id" >&2; exit 1; }
version=$(info_get "$bdir" version)
[[ -n $version ]] || { echo "build $id has no version (made without VERSION)" >&2; exit 1; }

# POS programs are in /pos/bin and /pos/sbin. The other images are Fedora
# layouts: they link most of them into /usr/bin, except where a Fedora
# package has the path, so /usr/bin comes first there.
name=pos
path=/pos/bin:/pos/sbin:/usr/local/bin:/usr/bin
if [[ $image != container ]]; then
  name=pos-${image#container-}
  path=/usr/local/bin:/usr/bin:/pos/bin:/pos/sbin
fi

if [[ -f $base/images/$image/containerfile ]]; then
  podman image exists "localhost/${name}:${id}" || {
    echo "build $id has no $image image in podman; make it with ./build image $image" >&2
    exit 1
  }
else
  archive=${bdir}/pos-image-${image}-$(build_stem "$bdir").tar.zst
  [[ -f $archive ]] || { echo "build $id has no $image image ($archive)" >&2; exit 1; }
  # As the host sees it: work may be a link, the checkout under /run/host.
  archive=$(realpath "$archive")
  podman import --change "ENV PATH=$path" \
    --change 'CMD ["/usr/bin/bash"]' \
    --change "LABEL pos.build=$id" --change "LABEL pos.version=$version" \
    "${archive#/run/host}" "localhost/${name}:${id}"
fi
podman tag "localhost/${name}:${id}" "localhost/${name}:${version}"
echo "localhost/${name}:${version} is build $id"
