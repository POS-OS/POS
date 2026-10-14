#!/usr/bin/env bash
# systemd's libseccomp version check (>= 2.4.0) is removed: both are built
# from this repository, and libseccomp's version is set by its prepare
# recipe, not by upstream's release process.
#
# systemd reads its drop-in directories (tmpfiles.d, sysusers.d, sysctl.d,
# modules-load.d, binfmt.d, udev/rules.d, ...) and kernel-install its
# plugins from /etc, /run, /usr/local/lib and /usr/lib only; the prefix is
# not among them, as it is for units. LIBDIR (<prefix>/lib) is added before
# /usr/lib, as units have the prefix before /usr/lib: POS's own files come
# from /pos/lib, and other packages' (Fedora's through pos-fedora, a hosted
# kernel's) are still read from /usr/lib.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
sed -i "/dependency('libseccomp'/,/get_option('seccomp')/ { /version : '>= 2.4.0',/d; }" \
    meson.build

sed -i 's|^\( *\)"/usr/lib/" n "\\0"|\1LIBDIR "/" n "\\0" \\\n&|
        s|^\( *\)"/usr/lib/" n$|\1LIBDIR "/" n, \\\n&|' \
    src/basic/constants.h src/shared/userdb-dropin.h
sed -i 's|"/usr/lib/kernel/install.d"|LIBDIR "/kernel/install.d", &|' \
    src/kernel-install/kernel-install.c
edits=$(cat src/basic/constants.h src/shared/userdb-dropin.h src/kernel-install/kernel-install.c |
          grep -c 'LIBDIR "/')
[[ $edits == 4 ]] || {
  echo "systemd: search paths not as expected" >&2
  exit 1
}
prep_finish
