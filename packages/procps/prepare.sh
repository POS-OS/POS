#!/usr/bin/env bash
# autogen.sh generates the build system. Its git-version-gen takes only a
# version starting with a digit, so the snapshot version is prefixed with
# the newest release in NEWS: 4.0.7-master-20261006-6e0855b87a0f.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
prep_version
release=$(sed -n 's/^procps-ng-\([0-9][0-9.]*\)$/\1/p' NEWS | head -1)
if [[ -z $release ]]; then
  echo "procps: no release found in NEWS" >&2
  exit 1
fi
printf '%s-%s\n' "$release" "$version" > .tarball-version
# The build writes these into the source tree when they are missing, as
# a release tarball has them: the .version stamp (as gettext's) and the
# compiled translations.
cp .tarball-version .version
for po in po/*.po; do
  msgfmt -c -o "${po%.po}.gmo" "$po"
done
prep_gen
prep_finish
