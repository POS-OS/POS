#!/usr/bin/env bash
# autogen.sh generates the build system and the translated man pages
# (po4a).

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
prep_gen
prep_finish
