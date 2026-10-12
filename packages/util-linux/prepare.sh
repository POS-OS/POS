#!/usr/bin/env bash
# autogen.sh generates the build system. The version comes from NEWS:
# its git-version-gen takes no snapshot version (it requires a leading digit).

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
prep_gen
prep_finish
