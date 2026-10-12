#!/usr/bin/env bash
# autopull.sh takes gnulib from src/gnulib; autogen.sh generates the build
# system.

set -euo pipefail

source "$POS_BASE/buildsys/prepare.sh"
require_container
prep_setup
prep_version
prep_pull
prep_gen
prep_finish
