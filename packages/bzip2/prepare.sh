#!/usr/bin/env bash
# Build system fixes.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
if [[ -f meson.build ]]; then
  # tests/meson.build requires pytest at configure time, even if tests are
  # not run.
  sed -i "/subdir('tests')/d" meson.build
elif [[ -f Makefile-libbz2_so ]]; then
  sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
  sed -i 's@(PREFIX)/man@(PREFIX)/share/man@g' Makefile
fi
prep_finish
