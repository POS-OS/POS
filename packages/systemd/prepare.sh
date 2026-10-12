#!/usr/bin/env bash
# systemd's libseccomp version check (>= 2.4.0) is removed: both are built
# from this repository, and libseccomp's version is set by its prepare
# recipe, not by upstream's release process.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
sed -i "/dependency('libseccomp'/,/get_option('seccomp')/ { /version : '>= 2.4.0',/d; }" \
    meson.build
prep_finish
