#!/usr/bin/env bash
# Put the packages' shipped defaults into /etc and /var of an image root:
# the factory-<package>.conf tmpfiles.d files (buildsys/pkg.sh pkg_factory)
# applied by the image's own systemd-tmpfiles, as a boot would. It runs
# through the image's loader, so /pos need not be installed where this
# runs. Used by image.sh and image-dnf.sh.
#
#   image-factory.sh <root>

set -euo pipefail

root=${1:?usage: image-factory.sh <root>}
confs=()
for f in "$root"/pos/lib/tmpfiles.d/factory-*.conf; do
  [[ -f $f ]] && confs+=("$f")
done
((${#confs[@]})) || exit 0
SYSTEMD_LOG_LEVEL=warning "$root/pos/lib/ld-linux-x86-64.so.2" \
  --library-path "$root/pos/lib:$root/pos/lib/systemd" \
  "$root/pos/bin/systemd-tmpfiles" --root="$root" --create "${confs[@]}"
