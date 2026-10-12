#!/usr/bin/env bash
# Shared libraries are linked without an rpath.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
if [[ -f support/shobj-conf ]]; then
  sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
fi
prep_finish
