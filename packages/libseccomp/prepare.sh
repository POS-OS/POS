#!/usr/bin/env bash
# autogen.sh generates the build system. main's configure.ac says
# AC_INIT([libseccomp], [0.0.0]); upstream sets the version when it cuts a
# release. The version is also the library's -version-number and
# SCMP_VER_* in seccomp.h, so 0.0.0 made the soname libseccomp.so.0
# (releases: .so.2). It is taken from the newest release in CHANGELOG.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
version=$(sed -n 's/^\* Version \([0-9][0-9.]*\) .*/\1/p' CHANGELOG | head -n 1)
if [[ -z $version ]]; then
  echo "libseccomp: no release version in CHANGELOG" >&2
  exit 1
fi
sed -i "s/^AC_INIT(\[libseccomp\], \[0\.0\.0\])/AC_INIT([libseccomp], [$version])/" configure.ac
grep -q "^AC_INIT(\[libseccomp\], \[$version\])" configure.ac || {
  echo "libseccomp: AC_INIT in configure.ac not as expected" >&2
  exit 1
}
prep_gen
prep_finish
